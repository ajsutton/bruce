import XCTest

@testable import Bruce

final class HomeAssistantAPIClientTests: XCTestCase {
  func testConnectionCheckAcceptsHomeAssistantStatus() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [.success(Data(#"{"message":"API running."}"#.utf8), statusCode: 200)]
    )
    try await session.install(fixture.credentials())
    let client = HomeAssistantAPIClient(session: session)

    let status = try await client.checkConnection()

    XCTAssertEqual(status, HomeAssistantAPIStatus(message: "API running."))
  }

  func testConnectionCheckRejectsAnIncompatiblePayload() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [.success(Data("{}".utf8), statusCode: 200)]
    )
    try await session.install(fixture.credentials())

    do {
      _ = try await HomeAssistantAPIClient(session: session).checkConnection()
      XCTFail("Expected an incompatible server response.")
    } catch HomeAssistantAPIError.incompatibleServer {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testConnectionCheckRejectsAnArbitraryMessage() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [.success(Data(#"{"message":"not Home Assistant"}"#.utf8), statusCode: 200)]
    )
    try await session.install(fixture.credentials())

    do {
      _ = try await HomeAssistantAPIClient(session: session).checkConnection()
      XCTFail("Expected an incompatible server response.")
    } catch HomeAssistantAPIError.incompatibleServer {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }
}
