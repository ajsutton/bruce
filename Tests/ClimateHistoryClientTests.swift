import XCTest

@testable import Bruce

final class ClimateHistoryClientTests: XCTestCase {
  func testHistoryRequestKeepsAttributesAndIncludesSystemAndDampers() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(apiResponses: [.success(Data("[]".utf8), statusCode: 200)])
    try await session.install(fixture.credentials())
    let interval = DateInterval(start: Date(timeIntervalSince1970: 100_000), duration: 12 * 3600)
    let history = try await HomeAssistantAPIClient(session: session).loadClimateHistory(
      interval: interval)
    XCTAssertEqual(history.interval, interval)
    let url = try XCTUnwrap(fixture.apiLoader.requests.first?.url)
    let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    XCTAssertFalse(
      items.contains {
        ["minimal_response", "no_attributes"].contains($0.name)
      })
    XCTAssertEqual(items.first { $0.name == "significant_changes_only" }?.value, "0")
    let entities = try XCTUnwrap(items.first { $0.name == "filter_entity_id" }?.value)
    XCTAssertEqual(
      Set(entities.split(separator: ",").map(String.init)), Set(ClimateHistoryZone.entityIDs))
    XCTAssertEqual(
      items.first { $0.name == "end_time" }?.value,
      interval.end.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
  }

  func testUnexpectedEntityIsRejected() throws {
    let data = Data(
      #"[[{"entity_id":"sensor.other","state":"off","attributes":{},"last_updated":"2026-09-24T00:00:00Z"}]]"#
        .utf8)
    XCTAssertThrowsError(
      try ClimateHistory(
        data: data, interval: DateInterval(start: .distantPast, end: .distantFuture)))
  }
}
