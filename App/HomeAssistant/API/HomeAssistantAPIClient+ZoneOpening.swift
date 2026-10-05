import Foundation

extension HomeAssistantAPIClient {
  func setOpening(_ value: Double, entityID: String) async throws {
    guard entityID.hasPrefix("cover."), value.isFinite,
      (0...100).contains(value), value.rounded() == value
    else {
      throw HomeAssistantAPIError.invalidResponse
    }
    let body = try JSONEncoder().encode(ZoneOpeningRequest(entityID: entityID, position: value))
    _ = try await session.authenticatedPOST(
      path: "api/services/cover/set_cover_position", body: body
    )
  }
}

private struct ZoneOpeningRequest: Encodable {
  let entityID: String
  let position: Double

  enum CodingKeys: String, CodingKey {
    case entityID = "entity_id"
    case position
  }
}
