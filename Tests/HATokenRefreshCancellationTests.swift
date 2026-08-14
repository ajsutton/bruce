import XCTest

@testable import Bruce

final class HATokenRefreshCancellationTests: XCTestCase {
  func testRefreshUsesExternalRouteWithoutWaitingForInternalRoute() async throws {
    let fixture = SessionFixture()
    let loader = RacingHomeAssistantLoader(
      blockedHost: fixture.internalURL.host() ?? "",
      successfulData: refreshedTokenResponse
    )
    let refresher = HomeAssistantTokenRefresher(
      authenticationClient: HomeAssistantAuthenticationClient(
        loader: loader,
        now: { [now = fixture.now] in now }
      )
    )

    let result = try await refresher.token(for: fixture.credentials())

    XCTAssertEqual(result.1, fixture.externalURL)
    XCTAssertTrue(loader.wasBlockedRouteCancelled)
    XCTAssertEqual(Set(loader.requestedHosts), Set(["home.local", "home.example"]))
  }

  func testCancellingOnlyRefreshWaiterReturnsPromptlyAndCancelsRefresh() async throws {
    let fixture = SessionFixture()
    let refreshLoader = BlockingHomeAssistantLoader()
    let session = makeSession(fixture: fixture, refreshLoader: refreshLoader)
    try await session.install(fixture.credentials(expiresAt: fixture.past))
    let completed = expectation(description: "Cancelled refresh waiter completed")
    let read = Task {
      defer { completed.fulfill() }
      return try await session.authenticatedGET(path: "api/")
    }
    await fulfillment(of: [refreshLoader.started], timeout: 1)

    read.cancel()

    await fulfillment(of: [completed], timeout: 1)
    do {
      _ = try await read.value
      XCTFail("Expected refresh cancellation.")
    } catch is CancellationError {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    XCTAssertTrue(refreshLoader.wasCancelled)
  }

  func testCancellingOneRefreshWaiterKeepsSharedRefreshForRemainingWaiter() async throws {
    let fixture = SessionFixture()
    let refreshLoader = BlockingHomeAssistantLoader()
    let bothWaitersRegistered = expectation(description: "Both refresh waiters registered")
    let refresher = makeRefresher(
      fixture: fixture,
      refreshLoader: refreshLoader,
      waiterRegistered: { count in
        if count == 2 {
          bothWaitersRegistered.fulfill()
        }
      }
    )
    let credentials = fixture.credentials()
    let cancelled = Task { [credentials] in
      try await refresher.token(for: credentials)
    }
    let remaining = Task { [credentials] in
      try await refresher.token(for: credentials)
    }
    await fulfillment(of: [refreshLoader.started], timeout: 1)
    await fulfillment(of: [bothWaitersRegistered], timeout: 1)

    cancelled.cancel()
    refreshLoader.succeed(with: refreshedTokenResponse, statusCode: 200)

    do {
      _ = try await cancelled.value
      XCTFail("Expected the first waiter to be cancelled.")
    } catch is CancellationError {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    let token = try await remaining.value
    XCTAssertEqual(token.0.accessToken, "refreshed-access")
    XCTAssertEqual(refreshLoader.requests.count, 2)
  }

  func testCompletedRefreshCannotSucceedAfterWaiterCancellation() async throws {
    let fixture = SessionFixture()
    let refreshLoader = BlockingHomeAssistantLoader()
    let cancellationDeferral = TokenRefreshCancellationDeferral()
    let refresher = HomeAssistantTokenRefresher(
      authenticationClient: makeAuthenticationClient(
        fixture: fixture,
        refreshLoader: refreshLoader
      ),
      cancellationDeferral: {
        await cancellationDeferral.wait()
      }
    )
    let credentials = fixture.credentials()
    let refresh = Task { [credentials] in
      try await refresher.token(for: credentials)
    }
    await fulfillment(of: [refreshLoader.started], timeout: 1)

    refresh.cancel()
    await fulfillment(of: [cancellationDeferral.started], timeout: 1)
    refreshLoader.succeed(with: refreshedTokenResponse, statusCode: 200)

    do {
      _ = try await refresh.value
      XCTFail("Expected refresh cancellation.")
    } catch is CancellationError {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    await cancellationDeferral.proceed()
  }

  func testRejectedRefreshIsReusedForLateWaiter() async throws {
    let fixture = SessionFixture()
    let refreshLoader = BlockingHomeAssistantLoader()
    let refresher = makeRefresher(fixture: fixture, refreshLoader: refreshLoader)
    let credentials = fixture.credentials()
    let first = Task { [credentials] in try await refresher.token(for: credentials) }
    await fulfillment(of: [refreshLoader.started], timeout: 1)
    refreshLoader.succeed(
      with: Data(#"{"error":"invalid_grant"}"#.utf8),
      statusCode: 400
    )

    await assertReauthenticationRequired(first)
    var routeUpdatedCredentials = credentials
    routeUpdatedCredentials.lastSuccessfulURL = fixture.externalURL
    let late = Task { [routeUpdatedCredentials] in
      try await refresher.token(for: routeUpdatedCredentials)
    }
    await assertReauthenticationRequired(late)

    XCTAssertEqual(refreshLoader.requests.count, 2)
  }

  private func makeSession(
    fixture: SessionFixture,
    refreshLoader: BlockingHomeAssistantLoader
  ) -> HomeAssistantSession {
    HomeAssistantSession(
      credentialStore: fixture.store,
      authenticationClient: HomeAssistantAuthenticationClient(
        loader: refreshLoader,
        now: { [now = fixture.now] in now }
      ),
      loader: fixture.apiLoader,
      now: { [now = fixture.now] in now }
    )
  }

  private func assertReauthenticationRequired(
    _ task: Task<HomeAssistantTokenRefresher.TokenResult, any Error>
  ) async {
    do {
      _ = try await task.value
      XCTFail("Expected reauthentication.")
    } catch {
      if case HomeAssistantAPIError.reauthenticationRequired = error {
      } else if !HomeAssistantRequestRouter.isRejectedRefresh(error) {
        XCTFail("Unexpected error: \(error)")
      }
    }
  }

  private func makeRefresher(
    fixture: SessionFixture,
    refreshLoader: BlockingHomeAssistantLoader,
    waiterRegistered: @escaping @Sendable (Int) -> Void = { _ in }
  ) -> HomeAssistantTokenRefresher {
    HomeAssistantTokenRefresher(
      authenticationClient: makeAuthenticationClient(
        fixture: fixture,
        refreshLoader: refreshLoader
      ),
      waiterRegistered: waiterRegistered
    )
  }

  private func makeAuthenticationClient(
    fixture: SessionFixture,
    refreshLoader: BlockingHomeAssistantLoader
  ) -> HomeAssistantAuthenticationClient {
    HomeAssistantAuthenticationClient(
      loader: refreshLoader,
      now: { [now = fixture.now] in now }
    )
  }

  private var refreshedTokenResponse: Data {
    Data(
      """
      {
        "access_token": "refreshed-access",
        "token_type": "Bearer",
        "expires_in": 1800
      }
      """.utf8
    )
  }
}

private actor TokenRefreshCancellationDeferral {
  nonisolated let started = XCTestExpectation(description: "Refresh cancellation was deferred")
  private var continuation: CheckedContinuation<Void, Never>?

  func wait() async {
    started.fulfill()
    await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
  }

  func proceed() {
    continuation?.resume()
    continuation = nil
  }
}
