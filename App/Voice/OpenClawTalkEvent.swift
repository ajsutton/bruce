struct OpenClawTalkEvent: Decodable, Sendable {
  struct Event: Decodable, Sendable {
    let sessionId: String
    let type: String
  }

  let voiceSessionId: String
  let talkEvent: Event

  func closes(_ id: String) -> Bool {
    voiceSessionId == id && talkEvent.sessionId == id && talkEvent.type == "session.closed"
  }
}
