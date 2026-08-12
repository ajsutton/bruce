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
  private var access: HomeAssistantAccessState?
  private var serverStatusTask: Task<Void, Never>?
  private var serverStatusGeneration = UUID()
  private var observationTasks: [HomeAssistantObservedFeature: Task<Void, Never>] = [:]
  private var observationGenerations: [HomeAssistantObservedFeature: UUID] = [:]
  private var activeFeatures: Set<HomeAssistantObservedFeature> = []
  private var isRefreshing = false
  private var isTransitioning = false
  private var transitionGeneration = UUID()
  private var observationGeneration = UUID()
  private var updatesSuspendedAt: Date?
  private var suspendedAccess: HomeAssistantAccessState?
  private var homeEnergyHistoryReuseDeadline: Date?
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

  func synchronize(with access: HomeAssistantAccessState) async {
    guard self.access != access || isTransitioning else { return }
    let generation = UUID()
    transitionGeneration = generation
    isTransitioning = true
    homeEnergyHistoryReuseDeadline = nil
    isRefreshing = false
    cancelObservations()
    serverStatusGeneration = UUID()
    serverStatusTask?.cancel()
    serverStatusTask = nil
    await resetStateFeed()
    guard transitionGeneration == generation else { return }
    guard !Task.isCancelled else {
      self.access = nil
      isTransitioning = false
      return
    }
    self.access = access
    isTransitioning = false
    updateServerStatus(for: access)
    guard !updateActivity.isSuspended else { return }
    startServerStatusObservation(for: access)
    HomeAssistantObservedFeature.allCases.forEach {
      startObservation($0, access: access)
    }
  }

  func refresh() async {
    guard
      access?.isReady == true,
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
    guard let access, access.isReady else { return }
    if refreshedActiveFeed {
      for feature in HomeAssistantObservedFeature.allCases
      where !activeFeatures.contains(feature) {
        startObservation(
          feature,
          access: access,
          homeEnergyHistoryReuseDeadline: homeEnergyHistoryReuseDeadline
        )
      }
    } else {
      restartServerStatusObservation(for: access)
      restartObservations(for: access)
    }
  }

  private func restartObservations(for access: HomeAssistantAccessState) {
    cancelObservations()
    HomeAssistantObservedFeature.allCases.forEach {
      startObservation(
        $0,
        access: access,
        homeEnergyHistoryReuseDeadline: homeEnergyHistoryReuseDeadline
      )
    }
  }

  private func cancelObservations() {
    observationTasks.values.forEach { $0.cancel() }
    observationTasks = [:]
    activeFeatures = []
  }

  private func updateServerStatus(for access: HomeAssistantAccessState) {
    switch access.phase {
    case .loading, .ready:
      serverStatus = HomeAssistantServerStatus(
        phase: .updating,
        lastSuccessfulUpdate: serverStatus.lastSuccessfulUpdate
      )
    case .requiresUserAction:
      serverStatus = HomeAssistantServerStatus(
        phase: .unavailable,
        lastSuccessfulUpdate: serverStatus.lastSuccessfulUpdate
      )
    case .signedOut:
      serverStatus = .idle
    }
  }

  private func startServerStatusObservation(for access: HomeAssistantAccessState) {
    guard access.isReady, let serverUpdates else { return }
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

  private func restartServerStatusObservation(for access: HomeAssistantAccessState) {
    serverStatusGeneration = UUID()
    serverStatusTask?.cancel()
    serverStatusTask = nil
    serverStatus = HomeAssistantServerStatus(
      phase: .updating,
      lastSuccessfulUpdate: serverStatus.lastSuccessfulUpdate
    )
    startServerStatusObservation(for: access)
  }

  private func startObservation(
    _ feature: HomeAssistantObservedFeature,
    access: HomeAssistantAccessState,
    homeEnergyHistoryReuseDeadline: Date? = nil
  ) {
    observationTasks[feature]?.cancel()
    let generation = UUID()
    observationGenerations[feature] = generation
    activeFeatures.insert(feature)
    let observe: @MainActor @Sendable () async -> Void =
      switch feature {
      case .temperature:
        { [temperatureStore] in
          await temperatureStore.synchronize(with: access)
        }
      case .charging:
        { [chargingStore] in
          await chargingStore.synchronize(with: access)
        }
      case .garageDoor:
        { [garageDoorStore] in
          await garageDoorStore.synchronize(with: access)
        }
      case .homeEnergy:
        { [homeEnergyStore] in
          await homeEnergyStore.synchronize(
            with: access,
            historyReuseDeadline: homeEnergyHistoryReuseDeadline
          )
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
    updatesSuspendedAt = now()
    suspendedAccess = access
    observationGeneration = UUID()
    isRefreshing = false
    homeEnergyStore.prepareForActivitySuspension()
    cancelObservations()
    serverStatusGeneration = UUID()
    serverStatusTask?.cancel()
    serverStatusTask = nil
    if access?.isReady == true {
      serverStatus = HomeAssistantServerStatus(
        phase: .updating,
        lastSuccessfulUpdate: serverStatus.lastSuccessfulUpdate
      )
    }
    await resetStateFeed()
  }

  private func resumeUpdates() {
    guard !isTransitioning, let access else { return }
    let historyReuseDeadline = updatesSuspendedAt.map {
      $0.addingTimeInterval(HomeEnergyHistorySampling.interval)
    }
    if suspendedAccess == access,
      let historyReuseDeadline,
      now() < historyReuseDeadline
    {
      homeEnergyHistoryReuseDeadline = historyReuseDeadline
    } else {
      homeEnergyHistoryReuseDeadline = nil
    }
    updatesSuspendedAt = nil
    suspendedAccess = nil
    updateServerStatus(for: access)
    startServerStatusObservation(for: access)
    HomeAssistantObservedFeature.allCases.forEach {
      startObservation(
        $0,
        access: access,
        homeEnergyHistoryReuseDeadline: homeEnergyHistoryReuseDeadline
      )
    }
  }
}
