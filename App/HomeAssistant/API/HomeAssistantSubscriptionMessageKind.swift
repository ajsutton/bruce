import Foundation

struct HomeAssistantSubscriptionMessageKind: Decodable {
  let type: String
}

struct HomeAssistantSubscriptionAuthentication: Encodable {
  let type: String
  let accessToken: String

  enum CodingKeys: String, CodingKey {
    case type
    case accessToken = "access_token"
  }
}

struct HomeAssistantEventSubscription: Encodable {
  let id: Int
  let type: String
  let eventType: String

  enum CodingKeys: String, CodingKey {
    case id
    case type
    case eventType = "event_type"
  }
}

struct HomeAssistantSubscriptionResult: Decodable {
  let id: Int
  let type: String
  let success: Bool
}

struct HomeAssistantStateChangedMessage: Decodable {
  let id: Int
  let type: String
  let event: HomeAssistantStateChangedEvent
}

struct HomeAssistantEventMessage: Decodable {
  let id: Int
  let type: String
  let event: HomeAssistantEvent
}

struct HomeAssistantEvent: Decodable {
  let eventType: String

  enum CodingKeys: String, CodingKey {
    case eventType = "event_type"
  }
}

struct HomeAssistantStateChangedEvent: Decodable {
  let eventType: String
  let data: HomeAssistantStateChangedData

  enum CodingKeys: String, CodingKey {
    case eventType = "event_type"
    case data
  }
}

struct HomeAssistantStateChangedData: Decodable {
  let entityID: String
  let newState: HomeAssistantState?
  let oldState: HomeAssistantState?

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    guard container.contains(.newState), container.contains(.oldState) else {
      throw DecodingError.keyNotFound(
        container.contains(.newState) ? CodingKeys.oldState : CodingKeys.newState,
        .init(
          codingPath: container.codingPath,
          debugDescription: "State changes require both new_state and old_state."
        )
      )
    }
    entityID = try container.decode(String.self, forKey: .entityID)
    newState = try container.decodeIfPresent(HomeAssistantState.self, forKey: .newState)
    oldState = try container.decodeIfPresent(HomeAssistantState.self, forKey: .oldState)
  }

  enum CodingKeys: String, CodingKey {
    case entityID = "entity_id"
    case newState = "new_state"
    case oldState = "old_state"
  }
}
