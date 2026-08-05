import Foundation

private enum HomeAssistantObservedFeature: CaseIterable {
  case temperature
  case charging
  case garageDoor
  case homeEnergy
}

@MainActor
final class HomeAssistantObservationCoordinator: ObservableObject {
  @Published private(set) var serverStatus = HomeAssistantServerStatus.idle

  private let temperatureStore: HomeAssistantTemperatureStore
  private let chargingStore: HomeAssistantEVChargingStore
  private let garageDoorStore: HomeAssistantGarageDoorStore
  private let homeEnergyStore: HomeAssistantHomeEnergyStore
  private let refreshStateFeed: @Sendable () async -> Bool
  private let resetStateFeed: @Sendable () async -> Void
  private let serverUpdates:
    (@Sendable () async -> HomeAssistantBufferedUpdateStream<HomeAssistantStateUpdate>)?
  private let now: @Sendable () -> Date
  private var connection: HomeAssistantConnectionState?
  private var serverStatusTask: Task<Void, Never>?
  private var serverStatusGeneration = UUID()
  private var observationTasks: [HomeAssistantObservedFeature: Task<Void, Never>] = [:]
  private var observationGenerations: [HomeAssistantObservedFeature: UUID] = [:]
  private var activeFeatures: Set<HomeAssistantObservedFeature> = []
  private var isRefreshing = false
  private var isTransitioning = false
  private var transitionGeneration = UUID()
  private var observationGeneration = UUID()
  private lazy var updateActivity = HomeAssistantObservationActivity(
    suspend: { [weak self] in await self?.suspendUpdates() },
    resume: { [weak self] in self?.resumeUpdates() }
  )

  init(
    temperatureStore: HomeAssistantTemperatureStore,
    chargingStore: HomeAssistantEVChargingStore,
    garageDoorStore: HomeAssistantGarageDoorStore,
    homeEnergyStore: HomeAssistantHomeEnergyStore,
    refreshStateFeed: @escaping @Sendable () async -> Bool = { false },
    resetStateFeed: @escaping @Sendable () async -> Void = {},
    serverUpdates:
      (@Sendable () async -> HomeAssistantBufferedUpdateStream<HomeAssistantStateUpdate>)? = nil,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.temperatureStore = temperatureStore
    self.chargingStore = chargingStore
    self.garageDoorStore = garageDoorStore
    self.homeEnergyStore = homeEnergyStore
    self.refreshStateFeed = refreshStateFeed
    self.resetStateFeed = resetStateFeed
    self.serverUpdates = serverUpdates
    self.now = now
  }

  deinit {
    observationTasks.values.forEach { $0.cancel() }
    serverStatusTask?.cancel()
  }

  func synchronize(with connection: HomeAssistantConnectionState) async {
    guard self.connection != connection || isTransitioning else { return }
    let generation = UUID()
    transitionGeneration = generation
    isTransitioning = true
    isRefreshing = false
    cancelObservations()
    serverStatusGeneration = UUID()
    serverStatusTask?.cancel()
    serverStatusTask = nil
    await resetStateFeed()
    guard transitionGeneration == generation else { return }
    guard !Task.isCancelled else {
      self.connection = nil
      isTransitioning = false
      return
    }
    self.connection = connection
    isTransitioning = false
    updateServerStatus(for: connection)
    guard !updateActivity.isSuspended else { return }
    startServerStatusObservation(for: connection)
    HomeAssistantObservedFeature.allCases.forEach {
      startObservation($0, connection: connection)
    }
  }

  func refresh() async {
    guard
      case .connected = connection,
      !isRefreshing,
      !isTransitioning,
      !updateActivity.isSuspended
    else { return }
    let generation = transitionGeneration
    let lifecycleGeneration = observationGeneration
    isRefreshing = true
    let refreshedActiveFeed = await refreshStateFeed()
    guard
      transitionGeneration == generation,
      observationGeneration == lifecycleGeneration,
      !updateActivity.isSuspended
    else { return }
    isRefreshing = false
    guard let connection, case .connected = connection else { return }
    if refreshedActiveFeed {
      for feature in HomeAssistantObservedFeature.allCases
      where !activeFeatures.contains(feature) {
        startObservation(feature, connection: connection)
      }
    } else {
      restartServerStatusObservation(for: connection)
      restartObservations(for: connection)
    }
  }

  private func restartObservations(for connection: HomeAssistantConnectionState) {
    cancelObservations()
    HomeAssistantObservedFeature.allCases.forEach {
      startObservation($0, connection: connection)
    }
  }

  private func cancelObservations() {
    observationTasks.values.forEach { $0.cancel() }
    observationTasks = [:]
    activeFeatures = []
  }

  private func updateServerStatus(for connection: HomeAssistantConnectionState) {
    switch connection {
    case .connecting, .connected:
      serverStatus = HomeAssistantServerStatus(
        phase: .updating,
        lastSuccessfulUpdate: serverStatus.lastSuccessfulUpdate
      )
    case .unavailable:
      serverStatus = HomeAssistantServerStatus(
        phase: .unavailable,
        lastSuccessfulUpdate: serverStatus.lastSuccessfulUpdate
      )
    case .disconnected:
      serverStatus = .idle
    }
  }

  private func startServerStatusObservation(for connection: HomeAssistantConnectionState) {
    guard case .connected = connection, let serverUpdates else { return }
    let generation = UUID()
    serverStatusGeneration = generation
    serverStatusTask = Task { [weak self, now] in
      do {
        guard
          !Task.isCancelled,
          self?.serverStatusGeneration == generation
        else {
          return
        }
        let updates = await serverUpdates()
        defer { updates.cancel() }
        guard
          !Task.isCancelled,
          self?.serverStatusGeneration == generation
        else {
          return
        }
        for try await update in updates {
          guard
            !Task.isCancelled,
            let self,
            serverStatusGeneration == generation
          else { return }
          serverStatus = serverStatus.receiving(update, at: now())
        }
        guard
          !Task.isCancelled,
          let self,
          serverStatusGeneration == generation
        else { return }
        serverStatus = HomeAssistantServerStatus(
          phase: .unavailable,
          lastSuccessfulUpdate: serverStatus.lastSuccessfulUpdate
        )
        serverStatusTask = nil
      } catch {
        guard
          !Task.isCancelled,
          let self,
          serverStatusGeneration == generation
        else { return }
        serverStatus = serverStatus.receiving(error: error)
        serverStatusTask = nil
      }
    }
  }

  private func restartServerStatusObservation(for connection: HomeAssistantConnectionState) {
    serverStatusGeneration = UUID()
    serverStatusTask?.cancel()
    serverStatusTask = nil
    serverStatus = HomeAssistantServerStatus(
      phase: .updating,
      lastSuccessfulUpdate: serverStatus.lastSuccessfulUpdate
    )
    startServerStatusObservation(for: connection)
  }

  private func startObservation(
    _ feature: HomeAssistantObservedFeature,
    connection: HomeAssistantConnectionState
  ) {
    observationTasks[feature]?.cancel()
    let generation = UUID()
    observationGenerations[feature] = generation
    activeFeatures.insert(feature)
    let observe: @MainActor @Sendable () async -> Void =
      switch feature {
      case .temperature:
        { [temperatureStore] in
          await temperatureStore.synchronize(with: connection)
        }
      case .charging:
        { [chargingStore] in
          await chargingStore.synchronize(with: connection)
        }
      case .garageDoor:
        { [garageDoorStore] in
          await garageDoorStore.synchronize(with: connection)
        }
      case .homeEnergy:
        { [homeEnergyStore] in
          await homeEnergyStore.synchronize(with: connection)
        }
      }
    observationTasks[feature] = Task { [weak self] in
      guard
        !Task.isCancelled,
        self?.observationGenerations[feature] == generation
      else {
        return
      }
      await observe()
      self?.finishObservation(feature, generation: generation)
    }
  }

  private func finishObservation(
    _ feature: HomeAssistantObservedFeature,
    generation: UUID
  ) {
    guard observationGenerations[feature] == generation else { return }
    observationTasks[feature] = nil
    activeFeatures.remove(feature)
  }
}

extension HomeAssistantObservationCoordinator {
  func observeUpdates(
    while isActive: Bool,
    registrationDidBegin: @MainActor @Sendable () -> Void = {}
  ) async {
    await updateActivity.observeUpdates(
      while: isActive,
      registrationDidBegin: registrationDidBegin
    )
  }

  private func suspendUpdates() async {
    observationGeneration = UUID()
    isRefreshing = false
    cancelObservations()
    serverStatusGeneration = UUID()
    serverStatusTask?.cancel()
    serverStatusTask = nil
    if case .connected = connection {
      serverStatus = HomeAssistantServerStatus(
        phase: .updating,
        lastSuccessfulUpdate: serverStatus.lastSuccessfulUpdate
      )
    }
    await resetStateFeed()
  }

  private func resumeUpdates() {
    guard !isTransitioning, let connection else { return }
    updateServerStatus(for: connection)
    startServerStatusObservation(for: connection)
    HomeAssistantObservedFeature.allCases.forEach {
      startObservation($0, connection: connection)
    }
  }
}
