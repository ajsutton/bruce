import Foundation

@testable import Bruce

enum TemperatureLoaderError: Error, Sendable {
  case connectionUnavailable
  case signInRequired
  case unexpectedRequest
}

final class QueueTemperatureLoader:
  HomeAssistantTemperatureLoading, @unchecked Sendable
{
  private let lock = NSLock()
  private var results: [Result<[HomeAssistantTemperatureReading], TemperatureLoaderError>]

  init(
    results: [Result<[HomeAssistantTemperatureReading], TemperatureLoaderError>]
  ) {
    self.results = results
  }

  func temperatureUpdates() -> HomeAssistantTemperatureUpdateStream {
    let result = lock.withLock {
      results.isEmpty ? .failure(.unexpectedRequest) : results.removeFirst()
    }
    return HomeAssistantTemperatureUpdateStream { continuation in
      switch result {
      case .success(let readings):
        continuation.yield(.live(readings))
        continuation.finish()
      case .failure(.connectionUnavailable):
        continuation.finish(throwing: URLError(.notConnectedToInternet))
      case .failure(.signInRequired):
        continuation.finish(throwing: HomeAssistantAPIError.reauthenticationRequired)
      case .failure(.unexpectedRequest):
        continuation.finish(throwing: TemperatureLoaderError.unexpectedRequest)
      }
    }
  }
}
