import Foundation
import XCTest

@testable import Bruce

final class OpenClawTalkSessionTests: XCTestCase {
  func testSDPOfferCarriesBrokerAndAccessCredentialsToTheGateway() throws {
    let origin = try CloudflareAccessOrigin(XCTUnwrap(URL(string: "https://gateway.example")))
    let access = CloudflareAccessSession(
      application: CloudflareAccessApplication(
        origin: origin, issuer: try XCTUnwrap(URL(string: "https://team.cloudflareaccess.com")),
        audience: "test"
      ), subject: "test", token: "test-access", expiresAt: .distantFuture
    )
    let session = OpenClawTalkSession(
      voiceSessionId: "test-call", clientSecret: "test-broker",
      offerUrl: "/plugins/openai/realtime/calls",
      clientControl: .init(owner: "gateway"), transport: "webrtc"
    )
    let request = try session.offerRequest(origin: origin, access: access, sdp: "v=0\r\n")
    XCTAssertEqual(
      request.url?.absoluteString, "https://gateway.example/plugins/openai/realtime/calls")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-broker")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Cf-Access-Token"), "test-access")
    XCTAssertEqual(request.httpBody, Data("v=0\r\n".utf8))
  }

  func testSDPOfferRejectsAProviderURLBeforeSendingGatewayCredentials() throws {
    let origin = try CloudflareAccessOrigin(XCTUnwrap(URL(string: "https://gateway.example")))
    let access = CloudflareAccessSession(
      application: CloudflareAccessApplication(
        origin: origin, issuer: try XCTUnwrap(URL(string: "https://team.cloudflareaccess.com")),
        audience: "test"
      ), subject: "test", token: "test-access", expiresAt: .distantFuture
    )
    let session = OpenClawTalkSession(
      voiceSessionId: "test-call", clientSecret: "test-broker",
      offerUrl: "https://other.example/offer",
      clientControl: .init(owner: "gateway"), transport: "webrtc"
    )
    XCTAssertThrowsError(try session.offerRequest(origin: origin, access: access, sdp: "offer"))
  }

  func testOnlyAClosedEventForTheCurrentCallEndsItsMedia() throws {
    let closed = OpenClawTalkEvent(
      voiceSessionId: "current", talkEvent: .init(sessionId: "current", type: "session.closed"))
    XCTAssertTrue(closed.closes("current"))
    XCTAssertFalse(closed.closes("another"))
    let mismatched = OpenClawTalkEvent(
      voiceSessionId: "current", talkEvent: .init(sessionId: "another", type: "session.closed"))
    XCTAssertFalse(mismatched.closes("current"))
    let recoverable = OpenClawTalkEvent(
      voiceSessionId: "current", talkEvent: .init(sessionId: "current", type: "session.error"))
    XCTAssertFalse(recoverable.closes("current"))
  }

  func testAgentPhotosAndConfiguredNamesDecodeFromTheGatewayRoster() throws {
    let json =
      #"{"id":"family","name":"Bruce — Family","identity":{"name":"Bruce","avatarUrl":"data:image/png;base64,AQID"}}"#
    let agent = try JSONDecoder().decode(OpenClawAgent.self, from: Data(json.utf8))
    XCTAssertEqual(agent.displayName, "Bruce — Family")
    XCTAssertEqual(agent.embeddedAvatar, Data([1, 2, 3]))
  }
}
