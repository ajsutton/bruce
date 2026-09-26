import Foundation

enum BruceSiriRequest<Value: Sendable> {
  static func run(
    waitForTimeout: @escaping @Sendable () async throws -> Void,
    operation: @escaping @Sendable () async throws -> Value
  ) async throws -> Value {
    try Task.checkCancellation()
    do {
      return try await withThrowingTaskGroup(of: Value.self) { group in
        group.addTask {
          try Task.checkCancellation()
          let value = try await operation()
          try Task.checkCancellation()
          return value
        }
        group.addTask {
          try await waitForTimeout()
          throw BruceSiriError.connectionUnavailable
        }
        defer { group.cancelAll() }
        guard let value = try await group.next() else { throw CancellationError() }
        try Task.checkCancellation()
        return value
      }
    } catch {
      try Task.checkCancellation()
      throw error
    }
  }
}
