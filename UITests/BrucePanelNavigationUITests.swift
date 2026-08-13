import XCTest

@MainActor
final class BrucePanelNavigationUITests: XCTestCase {
  private let screen = BrucePanelsScreen(application: XCUIApplication())

  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  override func tearDown() async throws {
    if testRun?.failureCount ?? 0 > 0 {
      screen.captureFailureArtifacts()
    }
    try await super.tearDown()
  }

  func testSelectingNonadjacentTabsShowsTheirPanels() {
    screen.launch()

    screen.selectEnergy()
    screen.selectClimate()
  }

  func testSwipingAcrossPanelContentSelectsAdjacentTabsInOrder() {
    screen.launch()

    screen.swipePanelLeft(to: .garage)
    screen.swipePanelLeft(to: .energy)
    screen.swipePanelRight(to: .garage)
    screen.swipePanelRight(to: .climate)
  }

  func testVerticalScrollingDoesNotChangeTheSelectedTab() {
    screen.launch()

    screen.scrollClimateVertically()
  }

  func testSwipingClimatePresetsDoesNotChangeTheSelectedTab() {
    screen.launch()

    screen.scrollClimatePresetsHorizontally()
  }
}
