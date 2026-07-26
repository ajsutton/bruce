import XCTest

@testable import Bruce

final class HomeAssistantCopyTests: XCTestCase {
  func testRoutineSetupAndSuccessCopyChangesWithBrandMode() {
    let standard = HomeAssistantCopy(mode: .standard)
    let full = HomeAssistantCopy(mode: .full)

    XCTAssertNotEqual(standard.introductionTitle, full.introductionTitle)
    XCTAssertNotEqual(standard.searching, full.searching)
    XCTAssertNotEqual(standard.searchInactive, full.searchInactive)
    XCTAssertNotEqual(standard.findHomeAssistant, full.findHomeAssistant)
    XCTAssertNotEqual(standard.enterAddressManually, full.enterAddressManually)
    XCTAssertNotEqual(standard.searchAgain, full.searchAgain)
    XCTAssertNotEqual(standard.chooseAnotherServer, full.chooseAnotherServer)
    XCTAssertNotEqual(standard.chooseDiscoveredHome, full.chooseDiscoveredHome)
    XCTAssertNotEqual(standard.manageConnection, full.manageConnection)
    XCTAssertNotEqual(standard.testConnection, full.testConnection)
    XCTAssertNotEqual(standard.changeServer, full.changeServer)
    XCTAssertNotEqual(standard.setUpHomeAssistant, full.setUpHomeAssistant)
    XCTAssertNotEqual(
      standard.connectedTitle(instanceName: "Home"),
      full.connectedTitle(instanceName: "Home")
    )
    XCTAssertNotEqual(standard.connectionSucceeded, full.connectionSucceeded)
    XCTAssertNotEqual(standard.notConnected, full.notConnected)
    XCTAssertNotEqual(standard.connectedStatus, full.connectedStatus)
    XCTAssertEqual(standard.connectionChecking, full.connectionChecking)
  }

  func testAuthenticationRecoveryCopyDoesNotChangeWithBrandMode() {
    let standard = HomeAssistantCopy(mode: .standard)
    let full = HomeAssistantCopy(mode: .full)

    for problem in authenticationProblems {
      XCTAssertEqual(
        standard.authenticationTitle(problem),
        full.authenticationTitle(problem)
      )
      XCTAssertEqual(
        standard.authenticationMessage(problem),
        full.authenticationMessage(problem)
      )
    }
  }

  func testValidationCopyDoesNotChangeWithBrandMode() {
    let standard = HomeAssistantCopy(mode: .standard)
    let full = HomeAssistantCopy(mode: .full)

    for error in validationErrors {
      XCTAssertEqual(
        standard.manualValidationMessage(error),
        full.manualValidationMessage(error)
      )
    }
  }

  func testSafetyAndRecoveryCopyDoesNotChangeWithBrandMode() {
    let standard = HomeAssistantCopy(mode: .standard)
    let full = HomeAssistantCopy(mode: .full)

    XCTAssertEqual(standard.restoringTitle, full.restoringTitle)
    XCTAssertEqual(standard.restoringDetail, full.restoringDetail)
    XCTAssertEqual(standard.localNetworkAccessOff, full.localNetworkAccessOff)
    XCTAssertEqual(standard.discoveryFailed, full.discoveryFailed)
    XCTAssertEqual(standard.unencryptedTitle, full.unencryptedTitle)
    XCTAssertEqual(standard.unencryptedMessage, full.unencryptedMessage)
    XCTAssertEqual(standard.onboardingTitle, full.onboardingTitle)
    XCTAssertEqual(standard.openingHomeAssistant, full.openingHomeAssistant)
    XCTAssertEqual(standard.connectionFailed, full.connectionFailed)
    XCTAssertEqual(standard.connectionFailedStatus, full.connectionFailedStatus)
    XCTAssertEqual(standard.reauthenticationRequired, full.reauthenticationRequired)
    XCTAssertEqual(standard.disconnectFailed, full.disconnectFailed)
    XCTAssertEqual(
      standard.recoveryChooseAnotherServer,
      full.recoveryChooseAnotherServer
    )
    XCTAssertEqual(standard.restoreFailedTitle, full.restoreFailedTitle)
    XCTAssertEqual(standard.restoreFailedMessage, full.restoreFailedMessage)
  }

  private var authenticationProblems: [HomeAssistantSetupStore.AuthenticationProblem] {
    [
      .rejected,
      .inactiveUser,
      .unavailable,
      .invalidCallback,
      .verificationFailed,
      .couldNotSave,
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
