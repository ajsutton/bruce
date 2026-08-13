import XCTest

@testable import Bruce

@MainActor
final class HomeAssistantConnectionVerificationTests: XCTestCase {
  func testMissingSessionCredentialsRequireReauthentication() async throws {
    let outcome = try await check(failingWith: HomeAssistantAPIError.noCredentials)

    assertConfigured(outcome, state: .reauthenticationRequired)
  }

  func testNetworkFailureProvidesAReachabilityReason() async throws {
    let outcome = try await check(failingWith: URLError(.cannotConnectToHost))

    assertConfigured(outcome, state: .failed(.networkUnavailable))
  }

  func testIncompatibleServerProvidesACompatibilityReason() async throws {
    let outcome = try await check(failingWith: HomeAssistantAPIError.incompatibleServer)

    assertConfigured(outcome, state: .failed(.incompatibleServer))
  }

  func testTLSErrorIsNotReportedAsAReachabilityFailure() async throws {
    let outcome = try await check(failingWith: URLError(.secureConnectionFailed))

    assertConfigured(outcome, state: .failed(.other))
  }

  func testAuthenticationServerErrorProvidesAServerRejectionReason() async throws {
    let outcome = try await check(
      failingWith: HomeAssistantAuthenticationError.serverRejectedRequest(
        statusCode: 503,
        description: nil
      )
    )

    assertConfigured(outcome, state: .failed(.serverRejectedRequest))
  }

  func testFailedChecksAndExpiredAuthenticationAllowSigningInAgain() {
    XCTAssertTrue(HomeAssistantSetupStore.ConnectionCheckState.failed(.other).canSignInAgain)
    XCTAssertTrue(
      HomeAssistantSetupStore.ConnectionCheckState.reauthenticationRequired.canSignInAgain
    )
    XCTAssertFalse(HomeAssistantSetupStore.ConnectionCheckState.succeeded.canSignInAgain)
  }

  func testCancellationWinsWhenAuthenticationFailureCompletes() async {
    let check = Task {
      try await self.check(failingWith: HomeAssistantAPIError.unauthorized)
    }
    check.cancel()

    do {
      _ = try await check.value
      XCTFail("Expected cancellation.")
    } catch is CancellationError {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  private func check(
    failingWith error: any Error
  ) async throws -> HomeAssistantConnectionVerification.Outcome {
    try await HomeAssistantConnectionVerification.check(
      using: FailingConnection(error: error),
      fallback: credentials
    )
  }

  private func assertConfigured(
    _ outcome: HomeAssistantConnectionVerification.Outcome,
    state: HomeAssistantSetupStore.ConnectionCheckState,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    guard case .configured(let configuredCredentials, let configuredState) = outcome else {
      return XCTFail("Expected a configured connection.", file: file, line: line)
    }
    XCTAssertEqual(configuredCredentials, credentials, file: file, line: line)
    XCTAssertEqual(configuredState, state, file: file, line: line)
  }

  private var credentials: HomeAssistantCredentials {
    HomeAssistantCredentials(
      instanceID: nil,
      instanceName: "Home",
      internalURL: URL(string: "https://home.example"),
      externalURL: nil,
      lastSuccessfulURL: URL(string: "https://home.example")
        ?? URL(fileURLWithPath: "/"),
      accessToken: "access",
      refreshToken: "refresh",
      tokenType: "Bearer",
      accessTokenExpiresAt: Date(timeIntervalSince1970: 30_000),
      clientID: HomeAssistantOAuthConfiguration.release.clientID
    )
  }
}

@MainActor
private final class FailingConnection: HomeAssistantConnecting {
  let error: any Error

  init(error: any Error) {
    self.error = error
  }

  func authenticate(
    to candidate: HomeAssistantConnectionCandidate
  ) async throws -> HomeAssistantCredentials {
    throw error
  }

  func restore() async throws -> HomeAssistantCredentials? {
    throw error
  }

  func testConnection() async throws -> HomeAssistantCredentials {
    throw error
  }

  func disconnect() async throws {
    throw error
  }

  func cancel() {}
}
