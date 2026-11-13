import Foundation

/// Keeps creation receipts until a cancelled startup can release its remote resources.
@MainActor
final class OpenClawTalkTransaction {
  private let gateway: any OpenClawRequesting
  private let exchangeOffer: @MainActor (URLRequest) async throws -> String
  private var conversationKey: String?
  private var physicalSessionID: String?
  private var isArchived = false
  private var creationRequest: OpenClawWireValue?
  private var needsReconciliation = false
  private var didConnect = false
  private var voiceSession: (key: String, id: String)?

  init(
    gateway: any OpenClawRequesting,
    exchangeOffer: @escaping @MainActor (URLRequest) async throws -> String =
      OpenClawTalkTransaction.exchange
  ) {
    self.gateway = gateway
    self.exchangeOffer = exchangeOffer
  }

  func start(agentID: String, offer: String, access: CloudflareAccessSession) async throws -> String
  {
    try Task.checkCancellation()
    didConnect = false
    isArchived = false
    physicalSessionID = nil
    let key = "agent:\(agentID):voice:\(UUID().uuidString.lowercased())"
    conversationKey = key
    let request = OpenClawWireValue.object([
      "key": .string(key), "agentId": .string(agentID),
      "idempotencyKey": .string(UUID().uuidString),
    ])
    creationRequest = request
    needsReconciliation = true
    try await recoverCreation()
    try Task.checkCancellation()
    let result = try await gateway.call(
      "talk.client.create",
      parameters: .object([
        "sessionKey": .string(key), "transport": .string("webrtc"),
        "capabilities": .array([.string("gateway-control-v1")]),
      ]), retainingReplyOnCancellation: true)
    let talk = try result.decode(OpenClawTalkSession.self)
    voiceSession = (key, talk.voiceSessionId)
    try Task.checkCancellation()
    let offerRequest = try talk.offerRequest(origin: access.origin, access: access, sdp: offer)
    return try await exchangeOffer(offerRequest)
  }

  func closes(_ event: OpenClawTalkEvent) -> Bool {
    guard let voiceSession else { return false }
    return event.closes(voiceSession.id)
  }

  func connected() {
    didConnect = true
    creationRequest = nil
    needsReconciliation = false
  }

  func reconcile() async throws {
    guard !didConnect, conversationKey != nil else { return }
    try await close()
  }

  private func recoverCreation() async throws {
    guard needsReconciliation, let creationRequest else { return }
    let result = try await gateway.call(
      "sessions.create", parameters: creationRequest, retainingReplyOnCancellation: true)
    guard result["key"]?.string == conversationKey, let physicalID = result["sessionId"]?.string,
      physicalSessionID == nil || physicalSessionID == physicalID
    else { throw OpenClawVoiceError.protocolFailure }
    physicalSessionID = physicalID
    needsReconciliation = false
  }

  func close() async throws {
    try await recoverCreation()
    let voice = voiceSession
    let abandonedKey = didConnect ? nil : conversationKey
    voiceSession = nil
    if didConnect { conversationKey = nil }
    var failure: (any Error)?
    if let voice {
      do {
        _ = try await gateway.call(
          "talk.client.close",
          parameters: .object([
            "sessionKey": .string(voice.key), "voiceSessionId": .string(voice.id),
          ]))
      } catch { failure = error }
    }
    if let abandonedKey, let physicalSessionID {
      do {
        if !isArchived {
          _ = try await gateway.call(
            "sessions.patch",
            parameters: .object([
              "key": .string(abandonedKey), "archived": .bool(true),
              "expectedSessionId": .string(physicalSessionID),
            ]))
          isArchived = true
        }
        _ = try await gateway.call(
          "sessions.delete",
          parameters: .object([
            "key": .string(abandonedKey), "archivedOnly": .bool(true),
            "expectedSessionId": .string(physicalSessionID),
          ]))
        clearAbandonedConversation()
      } catch {
        if try await ownedSessionIsGone() {
          clearAbandonedConversation()
        } else {
          failure = failure ?? error
        }
      }
    }
    if let failure { throw failure }
  }

  private func ownedSessionIsGone() async throws -> Bool {
    guard let physicalSessionID else { return false }
    let result = try await gateway.call(
      "sessions.resolve",
      parameters: .object([
        "sessionId": .string(physicalSessionID), "allowMissing": .bool(true),
      ]))
    switch result["ok"] {
    case .bool(false): return true
    case .bool(true): return false
    default: throw OpenClawVoiceError.protocolFailure
    }
  }

  private func clearAbandonedConversation() {
    conversationKey = nil
    creationRequest = nil
    physicalSessionID = nil
    isArchived = false
  }

  private static func exchange(_ request: URLRequest) async throws -> String {
    let (data, response) = try await CloudflareAccessClient.send(request, maximumBytes: 1_048_576)
    guard response.statusCode == 201 || response.statusCode == 200,
      let answer = String(data: data, encoding: .utf8), answer.hasPrefix("v=0")
    else { throw OpenClawVoiceError.unavailable }
    return answer
  }
}
