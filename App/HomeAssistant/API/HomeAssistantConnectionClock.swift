import Foundation

struct HomeAssistantConnectionClock: Sendable {
  let now: @Sendable () -> TimeInterval
  let sleep: @Sendable (Duration, Duration?) async throws -> Void

  init(
    now: @escaping @Sendable () -> TimeInterval = {
      ProcessInfo.processInfo.systemUptime
    },
    sleep: @escaping @Sendable (Duration, Duration?) async throws -> Void = { duration, tolerance in
      try await Task.sleep(for: duration, tolerance: tolerance)
    }
  ) {
    self.now = now
    self.sleep = sleep
  }
}
