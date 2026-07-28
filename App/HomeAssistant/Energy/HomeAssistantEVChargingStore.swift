import Foundation

@MainActor
final class HomeAssistantEVChargingStore: ObservableObject {
  @Published private(set) var mode: HomeAssistantEVChargingMode?
  @Published private(set) var isLoading = false
  @Published private(set) var isLive = false
  @Published private(set) var isChanging = false
  @Published private(set) var pendingMode: HomeAssistantEVChargingMode?
  @Published private(set) var problem: Problem?

  private let client: any HomeAssistantEVCharging
  private let onAuthenticationRequired: @MainActor @Sendable () -> Void
  private var operationGeneration = UUID()

  init(
    client: any HomeAssistantEVCharging,
    mode: HomeAssistantEVChargingMode? = nil,
    onAuthenticationRequired: @escaping @MainActor @Sendable () -> Void = {}
  ) {
    self.client = client
    self.mode = mode
    isLive = mode != nil
    self.onAuthenticationRequired = onAuthenticationRequired
  }

  var canSelectMode: Bool {
    isLive && !isChanging
  }

  func load() async {
    guard !isChanging else { return }
    let generation = UUID()
    operationGeneration = generation
    isLoading = true
    isLive = false
    problem = nil

    do {
      let loadedMode = try await client.loadEVChargingMode()
      try Task.checkCancellation()
      guard operationGeneration == generation else { return }
      mode = loadedMode
      isLoading = false
      isLive = true
    } catch is CancellationError {
      guard operationGeneration == generation else { return }
      isLoading = false
      isLive = false
    } catch {
      guard operationGeneration == generation else { return }
      guard !Task.isCancelled, !Self.isCancellation(error) else {
        isLoading = false
        isLive = false
        return
      }
      let loadProblem = Self.problem(for: error, operation: .loading)
      problem = loadProblem
      isLoading = false
      isLive = false
      if loadProblem == .signInRequired {
        onAuthenticationRequired()
      }
    }
  }

  func selectMode(_ requestedMode: HomeAssistantEVChargingMode) async {
    guard canSelectMode, requestedMode != mode else { return }
    let generation = UUID()
    operationGeneration = generation
    isChanging = true
    pendingMode = requestedMode
    problem = nil

    do {
      let confirmedMode = try await client.setEVChargingMode(requestedMode)
      try Task.checkCancellation()
      guard operationGeneration == generation else { return }
      mode = confirmedMode
      isChanging = false
      pendingMode = nil
      isLive = true
    } catch is CancellationError {
      guard operationGeneration == generation else { return }
      isChanging = false
      pendingMode = nil
      isLive = false
    } catch {
      guard operationGeneration == generation else { return }
      guard !Task.isCancelled, !Self.isCancellation(error) else {
        isChanging = false
        pendingMode = nil
        isLive = false
        return
      }
      let controlProblem = Self.problem(for: error, operation: .changing)
      problem = controlProblem
      isChanging = false
      pendingMode = nil
      isLive = false
      if controlProblem == .signInRequired {
        onAuthenticationRequired()
      }
    }
  }

  func markConnectionInProgress() {
    operationGeneration = UUID()
    isLoading = true
    isLive = false
    isChanging = false
    pendingMode = nil
    problem = nil
  }

  func markConnectionUnavailable() {
    operationGeneration = UUID()
    isLoading = false
    isLive = false
    isChanging = false
    pendingMode = nil
    if problem != .signInRequired {
      problem = .connectionNeedsManagement
    }
  }

  func reset() {
    operationGeneration = UUID()
    mode = nil
    isLoading = false
    isLive = false
    isChanging = false
    pendingMode = nil
    problem = nil
  }
}

extension HomeAssistantEVChargingStore {
  enum Problem: Equatable {
    case connectionNeedsManagement
    case connectionUnavailable
    case signInRequired
    case invalidResponse
    case updateFailed

    var message: String {
      switch self {
      case .connectionNeedsManagement:
        "The Home Assistant connection needs attention. The charging mode may be out of date."
      case .connectionUnavailable:
        "Home Assistant can’t be reached. The charging mode may be out of date."
      case .signInRequired:
        "Sign in to Home Assistant again to update the charging mode."
      case .invalidResponse:
        "Home Assistant returned a charging mode Bruce couldn’t read."
      case .updateFailed:
        "Bruce couldn’t change the charging mode."
      }
    }

    var needsConnectionManagement: Bool {
      self == .connectionNeedsManagement || self == .signInRequired
    }
  }

  private enum Operation {
    case loading
    case changing
  }

  private static func problem(
    for error: any Error,
    operation: Operation
  ) -> Problem {
    if HomeAssistantRequestRouter.isConnectivityFailure(error) {
      return .connectionUnavailable
    }
    guard let apiError = error as? HomeAssistantAPIError else {
      return operation == .loading ? .invalidResponse : .updateFailed
    }
    switch apiError {
    case .noCredentials, .unauthorized, .reauthenticationRequired:
      return .signInRequired
    case .invalidResponse, .incompatibleServer:
      return .invalidResponse
    case .invalidServerURL:
      return .connectionUnavailable
    case .server, .staleOperation:
      return operation == .loading ? .invalidResponse : .updateFailed
    }
  }

  private static func isCancellation(_ error: any Error) -> Bool {
    (error as? URLError)?.code == .cancelled
  }
}
