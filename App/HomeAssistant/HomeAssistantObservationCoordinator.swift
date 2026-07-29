import Foundation

@MainActor
final class HomeAssistantObservationCoordinator: ObservableObject {
  private enum Feature: CaseIterable {
    case temperature
    case charging
    case garageDoor
    case homeEnergy
  }

  private let temperatureStore: HomeAssistantTemperatureStore
  private let chargingStore: HomeAssistantEVChargingStore
  private let garageDoorStore: HomeAssistantGarageDoorStore
  private let homeEnergyStore: HomeAssistantHomeEnergyStore
  private let refreshStateFeed: @Sendable () async -> Bool
  private let resetStateFeed: @Sendable () async -> Void
  private var connection: HomeAssistantConnectionState?
  private var observationTasks: [Feature: Task<Void, Never>] = [:]
  private var observationGenerations: [Feature: UUID] = [:]
  private var activeFeatures: Set<Feature> = []
  private var isRefreshing = false
  private var isTransitioning = false
  private var transitionGeneration = UUID()

  init(
    temperatureStore: HomeAssistantTemperatureStore,
    chargingStore: HomeAssistantEVChargingStore,
    garageDoorStore: HomeAssistantGarageDoorStore,
    homeEnergyStore: HomeAssistantHomeEnergyStore,
    refreshStateFeed: @escaping @Sendable () async -> Bool = { false },
    resetStateFeed: @escaping @Sendable () async -> Void = {}
  ) {
    self.temperatureStore = temperatureStore
    self.chargingStore = chargingStore
    self.garageDoorStore = garageDoorStore
    self.homeEnergyStore = homeEnergyStore
    self.refreshStateFeed = refreshStateFeed
    self.resetStateFeed = resetStateFeed
  }

  deinit {
    observationTasks.values.forEach { $0.cancel() }
  }

  func synchronize(with connection: HomeAssistantConnectionState) async {
    guard self.connection != connection || isTransitioning else { return }
    let generation = UUID()
    transitionGeneration = generation
    isTransitioning = true
    isRefreshing = false
    cancelObservations()
    await resetStateFeed()
    guard transitionGeneration == generation else { return }
    guard !Task.isCancelled else {
      self.connection = nil
      isTransitioning = false
      return
    }
    self.connection = connection
    isTransitioning = false
    Feature.allCases.forEach { startObservation($0, connection: connection) }
  }

  func refresh() async {
    guard case .connected = connection, !isRefreshing, !isTransitioning else { return }
    let generation = transitionGeneration
    isRefreshing = true
    let refreshedActiveFeed = await refreshStateFeed()
    guard transitionGeneration == generation else { return }
    isRefreshing = false
    guard let connection, case .connected = connection else { return }
    if refreshedActiveFeed {
      for feature in Feature.allCases where !activeFeatures.contains(feature) {
        startObservation(feature, connection: connection)
      }
    } else {
      restartObservations(for: connection)
    }
  }

  private func restartObservations(for connection: HomeAssistantConnectionState) {
    cancelObservations()
    Feature.allCases.forEach { startObservation($0, connection: connection) }
  }

  private func cancelObservations() {
    observationTasks.values.forEach { $0.cancel() }
    observationTasks = [:]
    activeFeatures = []
  }

  private func startObservation(
    _ feature: Feature,
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

  private func finishObservation(_ feature: Feature, generation: UUID) {
    guard observationGenerations[feature] == generation else { return }
    observationTasks[feature] = nil
    activeFeatures.remove(feature)
  }
}
