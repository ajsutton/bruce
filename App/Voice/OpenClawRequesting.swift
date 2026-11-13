@MainActor
protocol OpenClawRequesting: AnyObject {
  func call(
    _ method: String, parameters: OpenClawWireValue, retainingReplyOnCancellation: Bool
  ) async throws -> OpenClawWireValue
}

extension OpenClawRequesting {
  func call(_ method: String, parameters: OpenClawWireValue = .object([:])) async throws
    -> OpenClawWireValue
  {
    try await call(method, parameters: parameters, retainingReplyOnCancellation: false)
  }
}
