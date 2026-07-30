import XCTest

@testable import Bruce

final class PriceHistoryIdentityTests: XCTestCase {
  func testPriceHistoryRequiresIdentityOnTheFirstState() async throws {
    try await assertInvalidHistory(
      Data(
        """
        [[
          {"state":"0.22","last_changed":"2026-07-29T10:00:00Z"},
          {
            "entity_id":"\(HomeAssistantHomeEnergySnapshot.generalPriceEntityID)",
            "state":"0.41",
            "last_changed":"2026-07-29T11:00:00Z"
          }
        ]]
        """.utf8
      )
    )
  }

  func testPriceHistoryRejectsAConflictingLaterIdentity() async throws {
    try await assertInvalidHistory(
      Data(
        """
        [[
          {
            "entity_id":"\(HomeAssistantHomeEnergySnapshot.generalPriceEntityID)",
            "state":"0.22",
            "last_changed":"2026-07-29T10:00:00Z"
          },
          {
            "entity_id":"\(HomeAssistantHomeEnergySnapshot.feedInPriceEntityID)",
            "state":"0.07",
            "last_changed":"2026-07-29T11:00:00Z"
          }
        ]]
        """.utf8
      )
    )
  }

  private func assertInvalidHistory(_ data: Data) async throws {
    let fixture = SessionFixture()
    let end = try date("2026-07-30T06:00:00Z")
    let session = fixture.makeSession(
      apiResponses: [.success(data, statusCode: 200)]
    )
    try await session.install(fixture.credentials())

    do {
      _ = try await HomeAssistantAPIClient(
        session: session,
        now: { end }
      ).loadHomeEnergyPriceHistory()
      XCTFail("Expected malformed price history to be rejected.")
    } catch HomeAssistantAPIError.invalidResponse {
    } catch {
      XCTFail("Unexpected price history error: \(error)")
    }
  }

  private func date(_ value: String) throws -> Date {
    try Date(
      value,
      strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: false)
    )
  }
}
