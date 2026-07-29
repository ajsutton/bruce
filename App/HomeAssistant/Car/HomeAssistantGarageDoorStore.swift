import Foundation

@MainActor
final class HomeAssistantGarageDoorStore: ObservableObject {
  @Published var doors: [HomeAssistantGarageDoorSnapshot]
  @Published private(set) var isLoading = false
  @Published private(set) var isLive: Bool
  @Published private(set) var isRefreshing = false
  @Published var problem: Problem?
  @Published var controlsInFlight: [String: Set<Control>] = [:]
  @Published var pendingDoorCommands: [String: HomeAssistantGarageDoorCommand] = [:]
  @Published private(set) var hasCompletedDiscovery: Bool

  private let loader: any HomeAssistantGarageDoorLoading
  let controller: (any HomeAssistantGarageDoorControlling)?
  let onAuthenticationRequired: @MainActor @Sendable () -> Void
  let commandTimeout: Duration
  let timeoutSleep: @Sendable (Duration) async -> Void
  private var observationGeneration = UUID()
  var commandTimeoutTasks: [String: Task<Void, Never>] = [:]
  var controlTimeoutTasks: [ControlOperationKey: Task<Void, Never>] = [:]
  var controlOperationIDs: [ControlOperationKey: UUID] = [:]
  var controlRequestedStates: [ControlOperationKey: ControlRequestedState] = [:]
  var doorOperationIDs: [String: UUID] = [:]
  var authoritativeDoors: [HomeAssistantGarageDoorSnapshot]

  init(
    loader: any HomeAssistantGarageDoorLoading,
    controller: (any HomeAssistantGarageDoorControlling)? = nil,
    doors: [HomeAssistantGarageDoorSnapshot] = [],
    isLive: Bool = false,
    hasCompletedDiscovery: Bool? = nil,
    commandTimeout: Duration = .seconds(8),
    timeoutSleep: @escaping @Sendable (Duration) async -> Void = {
      try? await Task.sleep(for: $0)
    },
    onAuthenticationRequired: @escaping @MainActor @Sendable () -> Void = {}
  ) {
    self.loader = loader
    self.controller = controller
    self.doors = doors
    self.isLive = isLive
    self.hasCompletedDiscovery = hasCompletedDiscovery ?? !doors.isEmpty
    self.commandTimeout = commandTimeout
    self.timeoutSleep = timeoutSleep
    self.onAuthenticationRequired = onAuthenticationRequired
    authoritativeDoors = doors
  }

  func synchronize(with connection: HomeAssistantConnectionState) async {
    switch connection {
    case .connected:
      await observeUpdates()
    case .disconnected:
      reset()
    case .connecting:
      invalidateObservation()
      invalidateControls()
      hasCompletedDiscovery = false
      isLoading = true
      problem = nil
    case .unavailable:
      invalidateObservation()
      invalidateControls()
      if problem != .signInRequired {
        problem = .connectionNeedsManagement
      }
    }
  }

  func reset() {
    observationGeneration = UUID()
    doors = []
    hasCompletedDiscovery = false
    isLoading = false
    isLive = false
    isRefreshing = false
    problem = nil
    authoritativeDoors = []
    invalidateControls()
  }
}

extension HomeAssistantGarageDoorStore {
  private func observeUpdates() async {
    let generation = UUID()
    observationGeneration = generation
    isLoading = !isRefreshing
    isLive = false
    problem = nil

    do {
      for try await update in loader.garageDoorUpdates() {
        try Task.checkCancellation()
        guard observationGeneration == generation else { return }
        apply(update)
      }
      try Task.checkCancellation()
      guard observationGeneration == generation else { return }
      if loader.providesContinuousUpdates {
        isLive = false
        problem = .connectionUnavailable
      }
      isLoading = false
      isRefreshing = false
    } catch is CancellationError {
      guard observationGeneration == generation else { return }
      isLoading = false
      isLive = false
      isRefreshing = false
    } catch {
      guard observationGeneration == generation, !Task.isCancelled else { return }
      let problem = Self.problem(for: error)
      self.problem = problem
      isLoading = false
      isLive = false
      isRefreshing = false
      if problem == .signInRequired {
        onAuthenticationRequired()
      }
    }
  }

  private func apply(
    _ update: HomeAssistantLiveUpdate<[HomeAssistantGarageDoorSnapshot]>
  ) {
    switch update {
    case .live(let doors):
      reconcileDoorCommands(with: doors)
      reconcileControls(with: doors)
      publish(doors)
      hasCompletedDiscovery = true
      isLoading = false
      isLive = true
      isRefreshing = false
      problem = nil
    case .refreshing(let doors):
      publish(doors)
      isLoading = false
      isLive = false
      isRefreshing = true
      problem = nil
    case .reconnecting(let doors):
      publish(doors)
      isLoading = false
      isLive = false
      isRefreshing = false
      problem = .reconnecting
    }
  }

  private func publish(_ doors: [HomeAssistantGarageDoorSnapshot]) {
    authoritativeDoors = doors
    self.doors = doors.map(applyingPendingControl)
  }

  private func invalidateObservation() {
    observationGeneration = UUID()
    isLoading = false
    isLive = false
    isRefreshing = false
  }

}
