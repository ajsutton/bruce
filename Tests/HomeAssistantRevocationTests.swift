import XCTest

@testable import Bruce

@MainActor
final class HomeAssistantRevocationTests: XCTestCase {
  func testBlockedRevocationDoesNotDelayLocalDisconnect() async throws {
    let fixture = CoordinatorFixture()
    let session = fixture.makeSession()
    try await session.install(fixture.existingCredentials())
    let revocationLoader = BlockingHomeAssistantLoader(honorsCancellation: false)
    let coordinator = HomeAssistantConnectionCoordinator(
      authenticationClient: HomeAssistantAuthenticationClient(
        loader: revocationLoader,
        now: { [now = fixture.now] in now }
      ),
      browser: fixture.browser,
      session: session,
      supervisor: RecordingConnectionSupervisor()
    )

    try await coordinator.disconnect()
    await fulfillment(of: [revocationLoader.started], timeout: 1)

    let currentCredentials = await session.currentCredentials()
    let storedCredentials = await fixture.store.value
    XCTAssertNil(currentCredentials)
    XCTAssertNil(storedCredentials)
    revocationLoader.succeed(with: Data(), statusCode: 200)
  }

  func testReleasingCoordinatorCancelsBlockedRevocation() async throws {
    let fixture = CoordinatorFixture()
    let session = fixture.makeSession()
    try await session.install(fixture.existingCredentials())
    let revocationLoader = BlockingHomeAssistantLoader()
    var coordinator: HomeAssistantConnectionCoordinator? = HomeAssistantConnectionCoordinator(
      authenticationClient: HomeAssistantAuthenticationClient(
        loader: revocationLoader,
        now: { [now = fixture.now] in now }
      ),
      browser: fixture.browser,
      session: session,
      supervisor: RecordingConnectionSupervisor()
    )
    weak let weakCoordinator = coordinator

    try await coordinator?.disconnect()
    await fulfillment(of: [revocationLoader.started], timeout: 1)
    coordinator = nil
    await fulfillment(of: [revocationLoader.cancellationObserved], timeout: 1)

    XCTAssertNil(weakCoordinator)
  }
}
