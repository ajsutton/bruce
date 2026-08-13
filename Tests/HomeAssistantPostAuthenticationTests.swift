import Combine
import XCTest

@testable import Bruce

@MainActor
final class HomeAssistantPostAuthenticationTests: XCTestCase {
  private func makeStore(
    connection: ControlledHomeAssistantConnection
  ) -> HomeAssistantSetupStore {
    HomeAssistantSetupAuthenticationTests().makeStore(connection: connection)
  }

  private func prepareManualCandidate(in store: HomeAssistantSetupStore) {
    HomeAssistantSetupAuthenticationTests().prepareManualCandidate(in: store)
  }

  private func credentials() -> HomeAssistantCredentials {
    HomeAssistantSetupAuthenticationTests().credentials()
  }

  func testSuccessfulOAuthShowsFinishingStateUntilFreshDataIsReady() async {
    let connection = ControlledHomeAssistantConnection()
    connection.blocksConnectionCheck = true
    let store = makeStore(connection: connection)
    prepareManualCandidate(in: store)

    store.requestAuthentication()
    await fulfillment(of: [connection.connectStarted], timeout: 1)
    connection.succeed(with: credentials())
    await fulfillment(of: [connection.connectionCheckStarted], timeout: 1)

    XCTAssertEqual(store.step, .finishingConnection(credentials()))
    XCTAssertEqual(store.connectedCredentials, credentials())
    XCTAssertEqual(store.connectionCheckState, .checking)

    connection.completeConnectionCheck(with: credentials())
  }

  func testPostAuthenticationFailureRetriesReadinessWithoutRepeatingOAuth() async {
    let connection = ControlledHomeAssistantConnection()
    connection.connectionCheckError = URLError(.notConnectedToInternet)
    let store = makeStore(connection: connection)
    let failureShown = expectation(description: "Post-authentication connection failure shown")
    let connected = expectation(description: "Retried connection completed")
    let subscription = store.$step.sink { step in
      if case .connectionFailed = step { failureShown.fulfill() }
      if case .connected = step { connected.fulfill() }
    }
    prepareManualCandidate(in: store)

    store.requestAuthentication()
    await fulfillment(of: [connection.connectStarted], timeout: 1)
    connection.succeed(with: credentials())
    await fulfillment(of: [failureShown], timeout: 1)

    XCTAssertEqual(store.step, .connectionFailed(credentials(), .networkUnavailable))
    XCTAssertEqual(store.connectedCredentials, credentials())
    XCTAssertEqual(connection.authenticationCount, 1)

    connection.connectionCheckError = nil
    store.retryConnection()
    await fulfillment(of: [connected], timeout: 1)

    XCTAssertEqual(store.step, .connected(credentials()))
    XCTAssertEqual(connection.authenticationCount, 1)
    XCTAssertEqual(connection.connectionCheckCount, 2)
    withExtendedLifetime(subscription) {}
  }
}
