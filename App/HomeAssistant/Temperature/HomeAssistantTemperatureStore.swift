import Foundation

enum HomeAssistantTemperatureUpdate: Equatable, Sendable {
  case live([HomeAssistantTemperatureReading])
  case reconnecting([HomeAssistantTemperatureReading])
}

protocol HomeAssistantTemperatureLoading: Sendable {
  func temperatureUpdates() -> AsyncThrowingStream<
    HomeAssistantTemperatureUpdate, any Error
  >
}

enum HomeAssistantTemperatureConnection: Equatable {
  case disconnected
  case connecting
  case connected(HomeAssistantCredentials)
  case unavailable
}

@MainActor
final class HomeAssistantTemperatureStore: ObservableObject {
  struct ControlProblem: Equatable {
    let message: String
  }

  enum Problem: Equatable {
    case connectionUnavailable
    case reconnecting
    case signInRequired
    case invalidResponse
    case other

    var message: String {
      switch self {
      case .connectionUnavailable:
        "Home Assistant can’t be reached. Temperatures may be out of date."
      case .reconnecting:
        "Reconnecting to Home Assistant. Temperatures may be out of date."
      case .signInRequired:
        "Sign in to Home Assistant again to update temperatures."
      case .invalidResponse:
        "Home Assistant returned temperature data Bruce couldn’t read."
      case .other:
        "Bruce couldn’t update the temperatures."
      }
    }
  }

  @Published private(set) var readings: [HomeAssistantTemperatureReading] = []
  @Published private(set) var lastChecked: Date?
  @Published private(set) var isLoading = false
  @Published private(set) var isLive = false
  @Published private(set) var problem: Problem?
  @Published private(set) var controllingEntityIDs: Set<String> = []
  @Published private(set) var controlProblem: ControlProblem?

  private let loader: any HomeAssistantTemperatureLoading
  private let controller: (any HomeAssistantClimateControlling)?
  private let now: @Sendable () -> Date
  private let confirmationTimeout: Duration
  private let sleep: @Sendable (Duration) async throws -> Void
  private let onAuthenticationRequired: @MainActor @Sendable () -> Void
  private var loadGeneration = UUID()
  private var controlGeneration = UUID()
  private var latestControlSequence = 0
  private var presentedControlProblemSequence: Int?
  private var serverReadings: [HomeAssistantTemperatureReading] = []
  private var pendingControls: [String: PendingClimateControl] = [:]
  private var confirmationTasks: [String: Task<Void, Never>] = [:]

  init(
    loader: any HomeAssistantTemperatureLoading,
    controller: (any HomeAssistantClimateControlling)? = nil,
    now: @escaping @Sendable () -> Date = Date.init,
    confirmationTimeout: Duration = .seconds(5),
    sleep: @escaping @Sendable (Duration) async throws -> Void = {
      try await Task.sleep(for: $0)
    },
    onAuthenticationRequired: @escaping @MainActor @Sendable () -> Void = {}
  ) {
    self.loader = loader
    self.controller = controller
    self.now = now
    self.confirmationTimeout = confirmationTimeout
    self.sleep = sleep
    self.onAuthenticationRequired = onAuthenticationRequired
  }

  func canControl(_ reading: HomeAssistantTemperatureReading) -> Bool {
    controller != nil && isLive && reading.powerState != .unavailable
  }

  var supportsControl: Bool {
    controller != nil
  }

  func isControlling(entityID: String) -> Bool {
    controllingEntityIDs.contains(entityID)
  }

  func setPower(
    for reading: HomeAssistantTemperatureReading,
    isOn: Bool
  ) async {
    guard let controller else {
      return
    }
    await performControl(for: reading, intent: .power(isOn: isOn)) {
      try await controller.setPower(entityID: reading.id, isOn: isOn)
    }
  }

  func setMode(
    _ mode: HomeAssistantTemperatureReading.ClimateMode,
    for reading: HomeAssistantTemperatureReading
  ) async {
    guard let controller, reading.availableModes.contains(mode) else {
      return
    }
    await performControl(for: reading, intent: .mode(mode)) {
      try await controller.setMode(mode, entityID: reading.id)
    }
  }

  func setTargetValue(
    _ value: Double,
    for reading: HomeAssistantTemperatureReading
  ) async {
    guard
      let controller,
      reading.kind == .zone,
      value.isFinite,
      reading.minimumTargetValue.map({ value >= $0 }) ?? true,
      reading.maximumTargetValue.map({ value <= $0 }) ?? true
    else {
      return
    }
    await performControl(for: reading, intent: .targetValue(value)) {
      try await controller.setTargetValue(value, entityID: reading.id)
    }
  }

  func dismissControlProblem() {
    controlProblem = nil
    presentedControlProblemSequence = nil
  }

  func synchronize(with connection: HomeAssistantTemperatureConnection) async {
    switch connection {
    case .connected:
      await load()
    case .disconnected:
      reset()
    case .connecting, .unavailable:
      invalidateLoad()
    }
  }

  func load() async {
    let generation = UUID()
    loadGeneration = generation
    isLoading = true
    isLive = false
    problem = nil

    do {
      for try await update in loader.temperatureUpdates() {
        try Task.checkCancellation()
        guard loadGeneration == generation else {
          return
        }
        apply(update)
      }
      try Task.checkCancellation()
      if loadGeneration == generation {
        isLoading = false
        isLive = false
      }
    } catch is CancellationError {
      guard loadGeneration == generation else {
        return
      }
      isLoading = false
      isLive = false
    } catch {
      guard loadGeneration == generation else {
        return
      }
      guard !Task.isCancelled, !Self.isCancellation(error) else {
        isLoading = false
        isLive = false
        return
      }
      let loadProblem = Self.problem(for: error)
      problem = loadProblem
      isLoading = false
      isLive = false
      if loadProblem == .signInRequired {
        onAuthenticationRequired()
      }
    }
  }

  func reset() {
    invalidateLoad()
    invalidateControls()
    serverReadings = []
    readings = []
    lastChecked = nil
    isLive = false
    problem = nil
  }

  private func invalidateLoad() {
    loadGeneration = UUID()
    isLoading = false
    isLive = false
  }

  private func invalidateControls() {
    controlGeneration = UUID()
    latestControlSequence += 1
    controllingEntityIDs = []
    pendingControls = [:]
    for task in confirmationTasks.values {
      task.cancel()
    }
    confirmationTasks = [:]
    controlProblem = nil
    presentedControlProblemSequence = nil
  }
}

extension HomeAssistantTemperatureStore {
  private func performControl(
    for reading: HomeAssistantTemperatureReading,
    intent: ClimateControlIntent,
    operation: () async throws -> Void
  ) async {
    guard canControl(reading), !controllingEntityIDs.contains(reading.id) else {
      return
    }
    let generation = controlGeneration
    latestControlSequence += 1
    let sequence = latestControlSequence
    controllingEntityIDs.insert(reading.id)
    pendingControls[reading.id] = PendingClimateControl(
      intent: intent,
      sequence: sequence,
      isAccepted: false
    )
    publishReadings()
    controlProblem = nil
    presentedControlProblemSequence = nil
    do {
      try await operation()
      guard controlGeneration == generation else {
        return
      }
      pendingControls[reading.id]?.isAccepted = true
      finishConfirmedControls()
      if pendingControls[reading.id]?.isAccepted == true {
        scheduleConfirmationTimeout(
          for: reading,
          generation: generation,
          sequence: sequence
        )
      }
    } catch is CancellationError {
      rejectControl(for: reading.id, generation: generation)
      return
    } catch {
      rejectControl(for: reading.id, generation: generation)
      guard !Self.isCancellation(error) else {
        return
      }
      guard
        controlGeneration == generation,
        !Task.isCancelled
      else {
        return
      }
      if Self.problem(for: error) == .signInRequired {
        onAuthenticationRequired()
      }
      reportControlProblem(for: reading.name, sequence: sequence)
    }
  }

  private func apply(_ update: HomeAssistantTemperatureUpdate) {
    switch update {
    case .live(let loadedReadings):
      serverReadings = loadedReadings
      finishConfirmedControls()
      lastChecked = now()
      isLoading = false
      isLive = true
      problem = nil
    case .reconnecting(let loadedReadings):
      serverReadings = loadedReadings
      publishReadings()
      isLoading = false
      isLive = false
      problem = .reconnecting
    }
  }
}

extension HomeAssistantTemperatureStore {
  fileprivate func finishConfirmedControls() {
    let confirmedEntityIDs: [String] = pendingControls.compactMap { element -> String? in
      let (entityID, control) = element
      guard control.isAccepted,
        let reading = serverReadings.first(where: { $0.id == entityID }),
        control.intent.matches(reading)
      else {
        return nil
      }
      return entityID
    }
    for entityID in confirmedEntityIDs {
      pendingControls.removeValue(forKey: entityID)
      controllingEntityIDs.remove(entityID)
      confirmationTasks.removeValue(forKey: entityID)?.cancel()
    }
    publishReadings()
  }

  fileprivate func rejectControl(for entityID: String, generation: UUID) {
    guard controlGeneration == generation else {
      return
    }
    pendingControls.removeValue(forKey: entityID)
    controllingEntityIDs.remove(entityID)
    confirmationTasks.removeValue(forKey: entityID)?.cancel()
    publishReadings()
  }

  fileprivate func scheduleConfirmationTimeout(
    for reading: HomeAssistantTemperatureReading,
    generation: UUID,
    sequence: Int
  ) {
    confirmationTasks[reading.id]?.cancel()
    confirmationTasks[reading.id] = Task { [weak self, sleep, confirmationTimeout] in
      do {
        try await sleep(confirmationTimeout)
      } catch {
        return
      }
      guard !Task.isCancelled else {
        return
      }
      self?.expireControl(
        for: reading.id,
        name: reading.name,
        generation: generation,
        sequence: sequence
      )
    }
  }

  fileprivate func expireControl(
    for entityID: String,
    name: String,
    generation: UUID,
    sequence: Int
  ) {
    guard
      controlGeneration == generation,
      let pendingControl = pendingControls[entityID],
      pendingControl.sequence == sequence,
      pendingControl.isAccepted
    else {
      return
    }
    rejectControl(for: entityID, generation: generation)
    reportControlProblem(for: name, sequence: sequence)
  }

  fileprivate func reportControlProblem(for name: String, sequence: Int) {
    if let presentedControlProblemSequence,
      presentedControlProblemSequence > sequence
    {
      return
    }
    presentedControlProblemSequence = sequence
    controlProblem = ControlProblem(
      message: "Bruce couldn’t update \(name)."
    )
  }

  fileprivate func publishReadings() {
    readings = serverReadings.map { reading in
      pendingControls[reading.id]?.intent.applying(to: reading) ?? reading
    }
  }
}
