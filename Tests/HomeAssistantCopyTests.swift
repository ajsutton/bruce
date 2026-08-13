import XCTest

@testable import Bruce

final class HomeAssistantCopyTests: XCTestCase {
  func testRoutineSetupAndConnectionCopyChangesWithBrandMode() {
    assertBrandCopyDiffers(\.navigationTitle)
    assertBrandCopyDiffers(\.introductionTitle)
    assertBrandCopyDiffers(\.introductionDescription)
    assertBrandCopyDiffers(\.searching)
    assertBrandCopyDiffers(\.noHomesFound)
    assertBrandCopyDiffers(\.findHomeAssistant)
    assertBrandCopyDiffers(\.enterAddressManually)
    assertBrandCopyDiffers(\.searchAgain)
    assertBrandCopyDiffers(\.chooseAnotherServer)
    assertBrandCopyDiffers(\.recoveryChooseAnotherServer)
    assertBrandCopyDiffers(\.restoringTitle)
    assertBrandCopyDiffers(\.restoringDetail)
    assertBrandCopyDiffers(\.localNetworkAccessOff)
    assertBrandCopyDiffers(\.discoveryFailed)
    assertBrandCopyDiffers(\.onboardingTitle)
    assertBrandCopyDiffers(\.openingHomeAssistant)
    assertBrandCopyDiffers(\.finishingConnectionTitle)
    assertBrandCopyDiffers(\.postAuthenticationFailureTitle)
    assertBrandCopyDiffers(\.connectionChecking)
    assertBrandCopyDiffers(\.connectionSucceeded)
    assertBrandCopyDiffers(\.reauthenticationRequired)
    assertBrandCopyDiffers(\.disconnectFailed)
    assertBrandCopyDiffers(\.restoreFailedTitle)
    assertBrandCopyDiffers(\.restoreFailedMessage)
  }

  func testAuthenticationAndRecoveryCopyChangesWithBrandMode() {
    let standard = HomeAssistantAuthenticationCopy(mode: .standard)
    let full = HomeAssistantAuthenticationCopy(mode: .full)

    for problem in authenticationProblems {
      XCTAssertNotEqual(
        standard.authenticationTitle(problem),
        full.authenticationTitle(problem)
      )
      XCTAssertNotEqual(
        standard.authenticationMessage(problem),
        full.authenticationMessage(problem)
      )
    }
    for error in validationErrors {
      XCTAssertNotEqual(
        standard.manualValidationMessage(error),
        full.manualValidationMessage(error)
      )
    }
  }

  func testConnectionFailuresKeepFullBruceVoice() {
    let standard = HomeAssistantSetupCopy(mode: .standard)
    let full = HomeAssistantSetupCopy(mode: .full)

    for problem in connectionCheckProblems {
      XCTAssertNotEqual(
        standard.connectionFailed(problem),
        full.connectionFailed(problem)
      )
      XCTAssertNotEqual(
        standard.connectionFailedStatus(problem),
        full.connectionFailedStatus(problem)
      )
      XCTAssertNotEqual(
        standard.connectionCheckAnnouncement(.failed(problem)),
        full.connectionCheckAnnouncement(.failed(problem))
      )
    }
  }

  func testTransportSecurityWarningRetainsFullBruceVoice() {
    let standard = HomeAssistantSetupCopy(mode: .standard)
    let full = HomeAssistantSetupCopy(mode: .full)
    let standardInterface = HomeAssistantInterfaceCopy(mode: .standard)
    let fullInterface = HomeAssistantInterfaceCopy(mode: .full)

    XCTAssertNotEqual(standard.unencryptedTitle, full.unencryptedTitle)
    XCTAssertNotEqual(standard.unencryptedMessage, full.unencryptedMessage)
    XCTAssertNotEqual(standardInterface.continueWithHTTP, fullInterface.continueWithHTTP)
    XCTAssertNotEqual(standardInterface.goBackFromHTTP, fullInterface.goBackFromHTTP)
    XCTAssertTrue(full.unencryptedMessage.contains("HTTP"))
    XCTAssertTrue(full.unencryptedMessage.contains("Home Assistant sign-in"))
  }

  func testFullBruceRetryActionsStateTheirIntent() {
    let setup = HomeAssistantSetupCopy(mode: .full)
    let interface = HomeAssistantInterfaceCopy(mode: .full)

    XCTAssertTrue(setup.searchAgain.contains("Search Again"))
    XCTAssertTrue(interface.signInAgain.contains("Sign In Again"))
    XCTAssertTrue(interface.retryAuthentication.contains("Sign-In Again"))
    XCTAssertTrue(interface.retryAuthentication.contains("Home Assistant"))
    XCTAssertTrue(interface.retryDiscovery.contains("Search"))
    XCTAssertTrue(interface.retryDiscovery.contains("Home Assistant"))
  }

  private func assertBrandCopyDiffers(
    _ keyPath: KeyPath<HomeAssistantSetupCopy, String>,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertNotEqual(
      HomeAssistantSetupCopy(mode: .standard)[keyPath: keyPath],
      HomeAssistantSetupCopy(mode: .full)[keyPath: keyPath],
      file: file,
      line: line
    )
  }

  private var authenticationProblems: [HomeAssistantSetupStore.AuthenticationProblem] {
    [
      .rejected,
      .inactiveUser,
      .browserUnavailable,
      .browserSessionEnded,
      .unavailable,
      .invalidCallback,
      .verificationFailed,
      .couldNotSave,
      .other,
    ]
  }

  private var connectionCheckProblems: [HomeAssistantSetupStore.ConnectionCheckProblem] {
    [
      .networkUnavailable,
      .serverRejectedRequest,
      .incompatibleServer,
      .invalidResponse,
      .other,
    ]
  }

  private var validationErrors: [HomeAssistantServerAddress.ValidationError] {
    [
      .empty,
      .unsupportedScheme,
      .missingHost,
      .containsCredentials,
      .containsQuery,
      .containsFragment,
      .pointsToEndpoint,
    ]
  }
}
