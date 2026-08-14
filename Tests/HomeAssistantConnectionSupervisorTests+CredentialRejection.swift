import Foundation
import XCTest

@testable import Bruce

extension HomeAssistantConnectionSupervisorTests {
  func testRejectedSessionRefreshCancelsSocketAndRequiresUserAction() async throws {
    let fixture = SupervisorFixture(snapshotValues: [21])
    fixture.authenticationLoader.results = [
      .success(Data(#"{"error":"invalid_grant"}"#.utf8), statusCode: 400)
    ]
    try await fixture.install()
    let connection = ScriptedHomeAssistantConnection()
    let supervisor = fixture.makeSupervisor(
      connector: ScriptedHomeAssistantConnector(connections: [connection])
    )
    let probe = AsyncThrowingStreamTestProbe(await supervisor.stateUpdates())
    await fulfillment(of: [probe.received(at: 0)], timeout: 5)

    do {
      try await fixture.session.refreshIfNeeded(force: true)
      XCTFail("Expected rejected refresh to require reauthentication.")
    } catch HomeAssistantAPIError.reauthenticationRequired {
    }
    await fulfillment(of: [connection.cancelled, probe.received(at: 1)], timeout: 5)

    let state = await supervisor.state
    let credentials = await fixture.session.currentCredentials()
    let storedCredentials = await fixture.store.value
    await probe.cancel()
    XCTAssertEqual(state, .requiresUserAction)
    XCTAssertNil(credentials)
    XCTAssertNil(storedCredentials)
  }
}
