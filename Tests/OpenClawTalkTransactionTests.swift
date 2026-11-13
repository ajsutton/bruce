import Foundation
import XCTest

@testable import Bruce

@MainActor
final class OpenClawTalkTransactionTests: XCTestCase {
  func testCancelledConversationCreationDeletesTheAbandonedConversation() async throws {
    try await checkCancelledCreation(
      method: "sessions.create", expected: ["sessions.create", "sessions.patch", "sessions.delete"])
  }

  func testCancelledTalkCreationClosesTheReturnedCallBeforeDeletingTheConversation() async throws {
    try await checkCancelledCreation(
      method: "talk.client.create",
      expected: [
        "sessions.create", "talk.client.create", "talk.client.close", "sessions.patch",
        "sessions.delete",
      ]
    )
  }

  func testConnectedCallUsesGatewayDefaultsAndPreservesItsConversationOnEnd() async throws {
    let gateway = TalkGatewayDouble()
    let transaction = OpenClawTalkTransaction(gateway: gateway, exchangeOffer: { _ in "v=0\r\n" })
    _ = try await transaction.start(agentID: "family", offer: "offer", access: access())
    transaction.connected()
    try await transaction.close()
    XCTAssertEqual(gateway.methods, ["sessions.create", "talk.client.create", "talk.client.close"])
    let request = try XCTUnwrap(gateway.talkRequest)
    XCTAssertNil(request["provider"])
    XCTAssertNil(request["model"])
    XCTAssertEqual(request["transport"]?.string, "webrtc")
  }

  func testLostCreationReplyIsReconciledWithTheOriginalIdempotencyKey() async throws {
    let gateway = TalkGatewayDouble()
    gateway.losesFirstCreateReply = true
    let transaction = OpenClawTalkTransaction(gateway: gateway, exchangeOffer: { _ in "v=0\r\n" })
    do {
      _ = try await transaction.start(agentID: "family", offer: "offer", access: access())
      XCTFail("Lost reply must fail startup")
    } catch let error as URLError {
      XCTAssertEqual(error.code, .networkConnectionLost)
    }
    try await transaction.reconcile()
    XCTAssertEqual(gateway.creationKeys.count, 2)
    XCTAssertEqual(gateway.creationKeys.first, gateway.creationKeys.last)
    XCTAssertEqual(gateway.idempotencyKeys.first, gateway.idempotencyKeys.last)
    XCTAssertEqual(
      gateway.methods, ["sessions.create", "sessions.create", "sessions.patch", "sessions.delete"])
  }

  func testLostDeleteReplyReconcilesTheMissingOriginalSession() async throws {
    let gateway = TalkGatewayDouble()
    gateway.losesFirstDeleteReply = true
    let transaction = OpenClawTalkTransaction(gateway: gateway, exchangeOffer: { _ in "v=0\r\n" })
    _ = try await transaction.start(agentID: "family", offer: "offer", access: access())
    do {
      try await transaction.close()
      XCTFail("Lost delete reply must be reported")
    } catch let error as URLError { XCTAssertEqual(error.code, .networkConnectionLost) }
    try await transaction.reconcile()
    XCTAssertEqual(
      gateway.methods,
      [
        "sessions.create", "talk.client.create", "talk.client.close", "sessions.patch",
        "sessions.delete", "sessions.resolve", "sessions.delete", "sessions.resolve",
      ])
    let settledMethods = gateway.methods
    try await transaction.reconcile()
    XCTAssertEqual(gateway.methods, settledMethods)
  }

  func testCleanupCannotArchiveAReplacementPhysicalSession() async throws {
    let gateway = TalkGatewayDouble()
    let transaction = OpenClawTalkTransaction(gateway: gateway, exchangeOffer: { _ in "v=0\r\n" })
    _ = try await transaction.start(agentID: "family", offer: "offer", access: access())
    gateway.physicalID = "replacement"
    try await transaction.close()
    let settledMethods = gateway.methods
    try await transaction.reconcile()
    XCTAssertEqual(gateway.methods, settledMethods)
    XCTAssertFalse(gateway.methods.contains("sessions.delete"))
  }

  private func checkCancelledCreation(method: String, expected: [String]) async throws {
    let gateway = TalkGatewayDouble()
    gateway.blockedMethod = method
    let sent = expectation(description: "Create request has reached the gateway")
    gateway.onBlocked = { sent.fulfill() }
    let transaction = OpenClawTalkTransaction(gateway: gateway, exchangeOffer: { _ in "v=0\r\n" })
    let access = try access()
    let start = Task {
      try await transaction.start(agentID: "family", offer: "offer", access: access)
    }
    await fulfillment(of: [sent], timeout: 2)
    start.cancel()
    gateway.releaseReply()
    do {
      _ = try await start.value
      XCTFail("Cancelled startup must not connect")
    } catch is CancellationError {
      // The transaction has retained the server's creation receipt for close().
    }
    try await transaction.close()
    XCTAssertEqual(gateway.methods, expected)
  }

  private func access() throws -> CloudflareAccessSession {
    let origin = try CloudflareAccessOrigin(XCTUnwrap(URL(string: "https://gateway.example")))
    return CloudflareAccessSession(
      application: CloudflareAccessApplication(
        origin: origin, issuer: try XCTUnwrap(URL(string: "https://team.cloudflareaccess.com")),
        audience: "test"
      ), subject: "test", token: "test-access", expiresAt: .distantFuture
    )
  }
}

@MainActor
private final class TalkGatewayDouble: OpenClawRequesting {
  var losesFirstCreateReply = false
  var losesFirstDeleteReply = false
  var physicalID = "physical-test"
  private var deleted = false
  private var resolutionFailures = 0
  var creationKeys: [String] = []
  var idempotencyKeys: [String] = []
  var blockedMethod: String?
  var onBlocked: (() -> Void)?
  var methods: [String] = []
  var talkRequest: OpenClawWireValue?
  private var reply: CheckedContinuation<Void, Never>?

  func call(
    _ method: String, parameters: OpenClawWireValue, retainingReplyOnCancellation: Bool
  ) async throws -> OpenClawWireValue {
    methods.append(method)
    if method == blockedMethod {
      XCTAssertTrue(retainingReplyOnCancellation)
      await withCheckedContinuation {
        reply = $0
        onBlocked?()
      }
    }
    switch method {
    case "sessions.create": return try create(parameters)
    case "sessions.resolve": return try resolve(parameters)
    case "sessions.patch", "sessions.delete": return try cleanup(method, parameters: parameters)
    case "talk.client.create":
      talkRequest = parameters
      return .object([
        "voiceSessionId": .string("test-call"), "clientSecret": .string("test-secret"),
        "offerUrl": .string("/plugins/openai/realtime/calls"), "transport": .string("webrtc"),
        "clientControl": .object(["owner": .string("gateway")]),
      ])
    default: return .object([:])
    }
  }

  private func cleanup(_ method: String, parameters: OpenClawWireValue) throws -> OpenClawWireValue
  {
    guard parameters["expectedSessionId"]?.string == physicalID, !deleted else {
      throw OpenClawVoiceError.protocolFailure
    }
    if method == "sessions.patch" {
      XCTAssertFalse(deleted, "A lost delete ACK must not re-archive a missing session")
      if case .bool(true) = parameters["archived"] {
      } else {
        XCTFail("Abandoned session must be archived")
      }
    } else {
      let wasDeleted = deleted
      deleted = true
      if losesFirstDeleteReply, !wasDeleted {
        resolutionFailures = 1
        throw URLError(.networkConnectionLost)
      }
      if case .bool(true) = parameters["archivedOnly"] {
      } else {
        XCTFail("Deletion must use the write-scoped archived-only path")
      }
    }
    return .object([:])
  }

  private func resolve(_ parameters: OpenClawWireValue) throws -> OpenClawWireValue {
    if resolutionFailures > 0 {
      resolutionFailures -= 1
      throw URLError(.networkConnectionLost)
    }
    return .object(["ok": .bool(!deleted && parameters["sessionId"]?.string == physicalID)])
  }

  private func create(_ parameters: OpenClawWireValue) throws -> OpenClawWireValue {
    let key = parameters["key"]?.string ?? "missing-key"
    creationKeys.append(key)
    idempotencyKeys.append(parameters["idempotencyKey"]?.string ?? "missing-idempotency")
    if losesFirstCreateReply, creationKeys.count == 1 { throw URLError(.networkConnectionLost) }
    return .object(["key": .string(key), "sessionId": .string(physicalID)])
  }

  func releaseReply() {
    reply?.resume()
    reply = nil
  }
}
