import Foundation

@MainActor
final class HomeAssistantTemperatureStore: ObservableObject {
  @Published private(set) var readings: [HomeAssistantTemperatureReading] = []
  @Published private(set) var lastChecked: Date?
  @Published private(set) var isLoading = false
  @Published private(set) var isLive = false
  @Published private(set) var isRefreshing = false
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
  private var targetControlTasks: [String: Task<Void, Never>] = [:]
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
  var supportsControl: Bool { controller != nil }
  func isAdjustingTarget(entityID: String) -> Bool {
    pendingControls[entityID]?.intent.isTargetValue == true
  }
  func setPower(
    for reading: HomeAssistantTemperatureReading,
    isOn: Bool
  ) async {
    guard let controller else { return }
    await performControl(for: reading, intent: .power(isOn: isOn)) { _ in
      try await controller.setPower(entityID: reading.id, isOn: isOn)
    }
  }
  func setMode(
    _ mode: HomeAssistantTemperatureReading.ClimateMode,
    for reading: HomeAssistantTemperatureReading
  ) async {
    guard let controller, reading.availableModes.contains(mode) else { return }
    await performControl(for: reading, intent: .mode(mode)) { _ in
      try await controller.setMode(mode, entityID: reading.id)
    }
  }

  func setTargetValue(
    _ value: Double,
    for reading: HomeAssistantTemperatureReading
  ) {
    guard let controller, reading.canSetTargetValue(value) else { return }
    let intent = ClimateControlIntent.targetValue(value)
    guard
      let attempt = beginControl(
        for: reading,
        intent: intent,
        allowsTargetReplacement: true
      ),
      attempt.shouldPerform
    else {
      return
    }
    targetControlTasks[reading.id] = Task { [weak self] in
      guard let self else { return }
      await performQueuedControl(
        for: reading,
        intent: intent,
        sequence: attempt.sequence,
        generation: attempt.generation
      ) { intent in
        guard case .targetValue(let latestValue) = intent else { return }
        try await controller.setTargetValue(latestValue, entityID: reading.id)
      }
      if controlGeneration == attempt.generation {
        targetControlTasks[reading.id] = nil
      }
    }
  }

  func dismissControlProblem() {
    controlProblem = nil
    presentedControlProblemSequence = nil
  }
  func synchronize(with connection: HomeAssistantConnectionState) async {
    switch connection {
    case .connected:
      await load()
    case .disconnected:
      reset()
    case .connecting, .unavailable:
      invalidateLoad()
      invalidateControls()
      publishReadings()
    }
  }

  func load() async {
    let generation = UUID()
    loadGeneration = generation
    let preservesRefreshPresentation = isRefreshing && problem == nil
    isLoading = !preservesRefreshPresentation
    if !preservesRefreshPresentation {
      isLive = false
      isRefreshing = false
      problem = nil
    }

    do {
      for try await update in loader.temperatureUpdates() {
        try Task.checkCancellation()
        guard loadGeneration == generation else { return }
        apply(update)
      }
      try Task.checkCancellation()
      if loadGeneration == generation {
        (isLoading, isLive, isRefreshing) = (false, false, false)
        problem = completionProblem
      }
    } catch is CancellationError {
      guard loadGeneration == generation else { return }
      (isLoading, isLive, isRefreshing) = (false, false, false)
    } catch {
      guard loadGeneration == generation else { return }
      guard !Task.isCancelled, !Self.isCancellation(error) else {
        (isLoading, isLive, isRefreshing) = (false, false, false)
        return
      }
      let loadProblem = Self.problem(for: error)
      problem = loadProblem
      (isLoading, isLive, isRefreshing) = (false, false, false)
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
    (isLive, isRefreshing) = (false, false)
    problem = nil
  }

  private func invalidateLoad() {
    loadGeneration = UUID()
    (isLoading, isLive, isRefreshing) = (false, false, false)
  }
  private var completionProblem: Problem? {
    loader.providesContinuousTemperatureUpdates ? .connectionUnavailable : nil
  }

  private func invalidateControls() {
    controlGeneration = UUID()
    latestControlSequence += 1
    controllingEntityIDs = []
    pendingControls = [:]
    confirmationTasks.values.forEach { $0.cancel() }
    confirmationTasks = [:]
    targetControlTasks.values.forEach { $0.cancel() }
    targetControlTasks = [:]
    controlProblem = nil
    presentedControlProblemSequence = nil
  }

  private func apply(_ update: HomeAssistantTemperatureUpdate) {
    let loadedReadings = update.readings
    if update.isLive || !loadedReadings.isEmpty || serverReadings.isEmpty {
      serverReadings = loadedReadings
    }
    switch update {
    case .live:
      finishConfirmedControls()
      lastChecked = now()
      (isLoading, isLive, isRefreshing, problem) = (false, true, false, nil)
    case .refreshing:
      publishReadings()
      (isLoading, isLive, isRefreshing, problem) = (false, false, true, nil)
    case .reconnecting:
      publishReadings()
      (isLoading, isLive, isRefreshing, problem) = (
        false, false, false, .reconnecting
      )
    }
  }
}

extension HomeAssistantTemperatureStore {
  private func performControl(
    for reading: HomeAssistantTemperatureReading,
    intent: ClimateControlIntent,
    allowsTargetReplacement: Bool = false,
    operation: (ClimateControlIntent) async throws -> Void
  ) async {
    guard !Task.isCancelled else { return }
    guard
      let attempt = beginControl(
        for: reading,
        intent: intent,
        allowsTargetReplacement: allowsTargetReplacement
      ),
      attempt.shouldPerform
    else {
      return
    }
    await performQueuedControl(
      for: reading,
      intent: intent,
      sequence: attempt.sequence,
      generation: attempt.generation,
      operation: operation
    )
  }

  private func beginControl(
    for reading: HomeAssistantTemperatureReading,
    intent: ClimateControlIntent,
    allowsTargetReplacement: Bool
  ) -> ClimateControlAttempt? {
    guard canControl(reading) else { return nil }
    let currentControl = pendingControls[reading.id]
    guard
      currentControl == nil
        || (allowsTargetReplacement && currentControl?.intent.isTargetValue == true)
    else { return nil }
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
    confirmationTasks.removeValue(forKey: reading.id)?.cancel()
    return ClimateControlAttempt(
      generation: controlGeneration,
      sequence: sequence,
      shouldPerform: currentControl?.isAccepted != false
    )
  }

  private func performQueuedControl(
    for reading: HomeAssistantTemperatureReading,
    intent: ClimateControlIntent,
    sequence: Int,
    generation: UUID,
    operation: (ClimateControlIntent) async throws -> Void
  ) async {
    var activeIntent = intent
    var activeSequence = sequence
    while true {
      guard controlGeneration == generation else { return }
      let result: Result<Void, any Error>
      do {
        try await operation(activeIntent)
        result = .success(())
      } catch {
        result = .failure(error)
      }
      guard controlGeneration == generation else { return }
      if let replacement = pendingControls[reading.id],
        replacement.sequence != activeSequence
      {
        activeIntent = replacement.intent
        activeSequence = replacement.sequence
        continue
      }
      switch result {
      case .success:
        pendingControls[reading.id]?.isAccepted = true
        finishConfirmedControls()
        if pendingControls[reading.id]?.isAccepted == true {
          scheduleConfirmationTimeout(
            for: reading,
            generation: generation,
            sequence: activeSequence
          )
        }
      case .failure(let error):
        rejectControl(for: reading.id, generation: generation)
        guard !Self.isCancellation(error), !Task.isCancelled else { return }
        if Self.problem(for: error) == .signInRequired { onAuthenticationRequired() }
        reportControlProblem(for: reading.name, sequence: activeSequence)
      }
      return
    }
  }

}

extension HomeAssistantTemperatureStore {
  private func finishConfirmedControls() {
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
    guard controlGeneration == generation else { return }
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
      } catch { return }
      guard !Task.isCancelled else { return }
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
    controlProblem = ControlProblem(name: name)
  }

  private func publishReadings() {
    readings = serverReadings.map { reading in
      pendingControls[reading.id]?.intent.applying(to: reading) ?? reading
    }
  }
}
