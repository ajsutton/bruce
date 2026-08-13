import Foundation

@MainActor
final class HomeAssistantTemperatureStore: ObservableObject {
  @Published private(set) var readings: [HomeAssistantTemperatureReading] = []
  private(set) var lastChecked: Date?
  @Published private(set) var isLoading = false
  @Published private(set) var isLive = false
  @Published private(set) var isRefreshing = false
  @Published private(set) var problem: Problem?
  @Published var controllingEntityIDs: Set<String> = []
  @Published var controlProblem: ControlProblem?
  let loader: any HomeAssistantTemperatureLoading
  let controller: (any HomeAssistantClimateControlling)?
  private let now: @Sendable () -> Date
  private let confirmationTimeout: Duration
  let sleep: @Sendable (Duration) async throws -> Void
  let onAuthenticationRequired: @MainActor @Sendable () -> Void
  private var loadGeneration = UUID()
  var activeObservationGeneration: UUID?
  var controlGeneration = UUID()
  var latestControlSequence = 0
  var presentedControlProblemSequence: Int?
  var serverReadings: [HomeAssistantTemperatureReading] = []
  var pendingControls: [String: PendingClimateControl] = [:]
  var confirmationTasks: [String: Task<Void, Never>] = [:]
  private var targetControlTasks: [String: Task<Void, Never>] = [:]
  var liveSequence = 0
  struct LiveWaiter {
    let baseline: Int
    let requiresControl: Bool
    var sawControl = false
    let continuation: CheckedContinuation<Void, any Error>
  }
  var liveWaiters: [UUID: LiveWaiter] = [:]
  var readinessLoadTask: Task<Void, Never>?
  var presetControlTask: Task<Void, Never>?
  var presetControlGeneration = UUID()
  var presetTransaction: PresetClimateTransaction?
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
      _ = await performQueuedControl(
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
  func synchronize(with access: HomeAssistantAccessState) async {
    switch access.phase {
    case .ready:
      readinessLoadTask?.cancel()
      readinessLoadTask = nil
      await load()
    case .signedOut:
      reset()
    case .loading, .requiresUserAction:
      invalidateLoad()
      invalidateControls()
      publishReadings()
    }
  }

  func load() async {
    await load(updates: loader.temperatureUpdates())
  }

  func load(updates: HomeAssistantTemperatureUpdateStream) async {
    let generation = UUID()
    loadGeneration = generation
    activeObservationGeneration = generation
    defer { finishObservation(generation: generation) }
    let preservesRefreshPresentation = isRefreshing && problem == nil
    isLoading = !preservesRefreshPresentation
    if !preservesRefreshPresentation {
      isLive = false
      isRefreshing = false
      problem = nil
    }

    do {
      for try await update in updates {
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
    readinessLoadTask?.cancel()
    readinessLoadTask = nil
    invalidateLoad()
    invalidateControls()
    serverReadings = []
    readings = []
    lastChecked = nil
    (isLive, isRefreshing) = (false, false)
    problem = nil
  }

  private func invalidateLoad() {
    cancelReadinessLoad()
    let waiters = liveWaiters.values
    liveWaiters = [:]
    waiters.forEach { $0.continuation.resume(throwing: CancellationError()) }
    loadGeneration = UUID()
    (isLoading, isLive, isRefreshing) = (false, false, false)
  }

  func cancelReadinessLoad() {
    readinessLoadTask?.cancel()
    readinessLoadTask = nil
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
    presetControlGeneration = UUID()
    presetControlTask?.cancel()
    presetControlTask = nil
    presetTransaction = nil
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
      liveSequence += 1
      let ready = liveWaiters.filter {
        liveSequence > $0.value.baseline
          && (!$0.value.requiresControl || $0.value.sawControl)
      }
      ready.forEach { liveWaiters.removeValue(forKey: $0.key)?.continuation.resume() }
      failPresetTransactionIfInvalid()
      finishConfirmedControls()
      lastChecked = now()
      if isLoading || !isLive || isRefreshing || problem != nil {
        (isLoading, isLive, isRefreshing, problem) = (false, true, false, nil)
      }
    case .refreshing:
      liveWaiters.keys.forEach { liveWaiters[$0]?.sawControl = true }
      publishReadings()
      (isLoading, isLive, isRefreshing, problem) = (false, false, true, nil)
    case .reconnecting:
      liveWaiters.keys.forEach { liveWaiters[$0]?.sawControl = true }
      publishReadings()
      (isLoading, isLive, isRefreshing, problem) = (
        false, false, false, .reconnecting
      )
    case .unavailable:
      let waiters = liveWaiters.values
      liveWaiters = [:]
      waiters.forEach {
        $0.continuation.resume(throwing: HomeAssistantAPIError.invalidResponse)
      }
      publishReadings()
      (isLoading, isLive, isRefreshing, problem) = (
        false, false, false, .connectionUnavailable
      )
    }
  }
}

extension HomeAssistantTemperatureStore {
  func finishConfirmedControls() {
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
    completePresetTransactionIfConfirmed()
    publishReadings()
  }

  func rejectControl(
    for entityID: String,
    generation: UUID,
    publishesReadings: Bool = true
  ) {
    guard controlGeneration == generation else { return }
    pendingControls.removeValue(forKey: entityID)
    controllingEntityIDs.remove(entityID)
    confirmationTasks.removeValue(forKey: entityID)?.cancel()
    if publishesReadings {
      publishReadings()
    }
  }

  func scheduleConfirmationTimeout(
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
    if failPresetTransactionIfNeeded(for: entityID) {
      reportControlProblem(for: name, sequence: sequence)
      return
    }
    rejectControl(for: entityID, generation: generation)
    reportControlProblem(for: name, sequence: sequence)
  }

  func reportControlProblem(for name: String, sequence: Int) {
    if let presentedControlProblemSequence,
      presentedControlProblemSequence > sequence
    {
      return
    }
    presentedControlProblemSequence = sequence
    controlProblem = ControlProblem(name: name)
  }

  func publishReadings() {
    let presentedReadings = serverReadings.map { reading in
      pendingControls[reading.id]?.intent.applying(to: reading) ?? reading
    }
    if !HomeAssistantTemperaturePresentation.matches(readings, presentedReadings) {
      readings = presentedReadings
    }
  }
}
