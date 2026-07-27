import Foundation

protocol HomeAssistantTemperatureLoading: Sendable {
  func loadTemperatures() async throws -> [HomeAssistantTemperatureReading]
}

enum HomeAssistantTemperatureConnection: Equatable {
  case disconnected
  case connecting
  case connected(HomeAssistantCredentials)
  case unavailable
}

@MainActor
final class HomeAssistantTemperatureStore: ObservableObject {
  enum Problem: Equatable {
    case connectionUnavailable
    case signInRequired
    case invalidResponse
    case other

    var message: String {
      switch self {
      case .connectionUnavailable:
        "Home Assistant can’t be reached. Temperatures may be out of date."
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
  @Published private(set) var problem: Problem?

  private let loader: any HomeAssistantTemperatureLoading
  private let now: @Sendable () -> Date
  private let onAuthenticationRequired: @MainActor @Sendable () -> Void
  private var loadGeneration = UUID()

  init(
    loader: any HomeAssistantTemperatureLoading,
    now: @escaping @Sendable () -> Date = Date.init,
    onAuthenticationRequired: @escaping @MainActor @Sendable () -> Void = {}
  ) {
    self.loader = loader
    self.now = now
    self.onAuthenticationRequired = onAuthenticationRequired
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
    problem = nil

    do {
      let loadedReadings = try await loader.loadTemperatures()
      try Task.checkCancellation()
      guard loadGeneration == generation else {
        return
      }
      readings = loadedReadings
      lastChecked = now()
      isLoading = false
    } catch is CancellationError {
      guard loadGeneration == generation else {
        return
      }
      isLoading = false
    } catch {
      guard loadGeneration == generation else {
        return
      }
      guard !Task.isCancelled, !Self.isCancellation(error) else {
        isLoading = false
        return
      }
      let loadProblem = Self.problem(for: error)
      problem = loadProblem
      isLoading = false
      if loadProblem == .signInRequired {
        onAuthenticationRequired()
      }
    }
  }

  func reset() {
    invalidateLoad()
    readings = []
    lastChecked = nil
    problem = nil
  }

  private func invalidateLoad() {
    loadGeneration = UUID()
    isLoading = false
  }

  private static func problem(for error: any Error) -> Problem {
    if HomeAssistantRequestRouter.isConnectivityFailure(error) {
      return .connectionUnavailable
    }
    guard let apiError = error as? HomeAssistantAPIError else {
      return .other
    }
    switch apiError {
    case .noCredentials, .unauthorized, .reauthenticationRequired:
      return .signInRequired
    case .invalidResponse, .incompatibleServer:
      return .invalidResponse
    case .invalidServerURL:
      return .connectionUnavailable
    case .server, .staleOperation:
      return .other
    }
  }

  private static func isCancellation(_ error: any Error) -> Bool {
    (error as? URLError)?.code == .cancelled
  }
}
