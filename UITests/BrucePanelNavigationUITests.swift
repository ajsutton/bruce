import XCTest

@MainActor
final class BrucePanelNavigationUITests: XCTestCase {
  private let screen = BrucePanelsScreen(application: XCUIApplication())

  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  override func tearDown() {
    if testRun?.failureCount ?? 0 > 0 {
      screen.captureFailureArtifacts()
    }
    super.tearDown()
  }

  func testSelectingNonadjacentTabsScrollsToTheirSections() {
    screen.launch()

    screen.selectEnergy()
    screen.selectClimate()
  }
}
