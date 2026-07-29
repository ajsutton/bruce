import XCTest

@testable import Bruce

final class GarageDoorControlClientTests: XCTestCase {
  func testGarageControlsCallEntitySpecificHomeAssistantServices() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: Array(
        repeating: .success(Data("[]".utf8), statusCode: 200),
        count: 5
      )
    )
    try await session.install(fixture.credentials())
    let client = HomeAssistantAPIClient(session: session)

    try await client.setGarageLight(entityID: "light.garage", isOn: true)
    try await client.setGarageLock(entityID: "lock.garage", isLocked: true)
    try await client.sendGarageDoorCommand(.open, entityID: "cover.garage")
    try await client.sendGarageDoorCommand(.close, entityID: "cover.garage")
    try await client.sendGarageDoorCommand(.stop, entityID: "cover.garage")

    XCTAssertEqual(
      fixture.apiLoader.requests.compactMap(\.url?.path),
      [
        "/api/services/light/turn_on",
        "/api/services/lock/lock",
        "/api/services/cover/open_cover",
        "/api/services/cover/close_cover",
        "/api/services/cover/stop_cover",
      ]
    )
    XCTAssertEqual(
      try fixture.apiLoader.requests.map {
        try JSONDecoder().decode(
          EntityTarget.self,
          from: XCTUnwrap($0.httpBody)
        ).entityID
      },
      [
        "light.garage",
        "lock.garage",
        "cover.garage",
        "cover.garage",
        "cover.garage",
      ]
    )
  }
}

private struct EntityTarget: Decodable {
  let entityID: String

  enum CodingKeys: String, CodingKey {
    case entityID = "entity_id"
  }
}
