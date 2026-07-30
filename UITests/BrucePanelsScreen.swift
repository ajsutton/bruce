import XCTest

@MainActor
final class BrucePanelsScreen {
  private let application: XCUIApplication
  private(set) var actionTrace: [String] = []
  private(set) var launchArguments: [String] = []
  private(set) var seed = ""
  private var sectionTop: CGFloat?

  init(application: XCUIApplication) {
    self.application = application
  }

  func launch() {
    seed = "panel-navigation-v1"
    launchArguments = [
      "-AppleLanguages", "(en)",
      "-AppleLocale", "en_AU",
      "-selectedPanel", "climate",
    ]
    application.launchArguments = launchArguments
    application.launchEnvironment["BRUCE_UI_TEST_SEED"] = seed
    record("Launch with the climate panel selected")
    application.launch()

    waitForExistence(
      application.descendants(matching: .any)[
        BruceAccessibilityIdentifier.panelTestContentReady
      ],
      description: "the deterministic panel content"
    )
    let climateSection = section(BruceAccessibilityIdentifier.climatePanelSection)
    waitForExistence(climateSection, description: "the Climate section")
    sectionTop = climateSection.frame.minY
    waitForSelection(
      tab(BruceAccessibilityIdentifier.climatePanelTab),
      description: "the Climate tab to be selected"
    )
  }

  func selectEnergy() {
    select(
      tabIdentifier: BruceAccessibilityIdentifier.energyPanelTab,
      sectionIdentifier: BruceAccessibilityIdentifier.energyPanelSection,
      name: "Energy"
    )
  }

  func selectClimate() {
    select(
      tabIdentifier: BruceAccessibilityIdentifier.climatePanelTab,
      sectionIdentifier: BruceAccessibilityIdentifier.climatePanelSection,
      name: "Climate"
    )
  }

  func captureFailureArtifacts() {
    let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    screenshot.name = "Failure screenshot"
    screenshot.lifetime = .keepAlways
    XCTContext.runActivity(named: "UI test failure artifacts") { activity in
      activity.add(screenshot)
      activity.add(
        attachment(named: "Accessibility hierarchy", value: application.debugDescription)
      )
      activity.add(attachment(named: "Action trace", value: actionTrace.joined(separator: "\n")))
      activity.add(
        attachment(
          named: "Launch configuration",
          value: "Arguments: \(launchArguments)\nSeed: \(seed)"
        )
      )
    }
  }

  private func select(
    tabIdentifier: String,
    sectionIdentifier: String,
    name: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    record("Tap the \(name) tab")
    let targetTab = tab(tabIdentifier)
    waitForElement(targetTab, description: "the \(name) tab", file: file, line: line)
    targetTab.tap()

    waitForSelection(
      tab(tabIdentifier),
      description: "the \(name) tab to be selected",
      file: file,
      line: line
    )
    waitForSectionAtTop(
      section(sectionIdentifier),
      description: "the \(name) section to scroll to the top",
      file: file,
      line: line
    )
  }

  private func tab(_ identifier: String) -> XCUIElement {
    application.buttons[identifier]
  }

  private func section(_ identifier: String) -> XCUIElement {
    application.staticTexts[identifier]
  }

  private func waitForElement(
    _ element: XCUIElement,
    description: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let predicate = NSPredicate(format: "exists == true AND hittable == true")
    wait(
      for: predicate,
      element: element,
      description: description,
      file: file,
      line: line
    )
  }

  private func waitForExistence(
    _ element: XCUIElement,
    description: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    wait(
      for: NSPredicate(format: "exists == true"),
      element: element,
      description: description,
      file: file,
      line: line
    )
  }

  private func waitForSelection(
    _ element: XCUIElement,
    description: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    wait(
      for: NSPredicate(format: "exists == true AND selected == true"),
      element: element,
      description: description,
      file: file,
      line: line
    )
  }

  private func waitForSectionAtTop(
    _ element: XCUIElement,
    description: String,
    file: StaticString,
    line: UInt
  ) {
    guard let sectionTop else {
      XCTFail("The initial panel position was not recorded.", file: file, line: line)
      return
    }
    let tolerance: CGFloat = 2
    let predicate = NSPredicate { candidate, _ in
      guard let candidate = candidate as? XCUIElement else {
        return false
      }
      return candidate.exists
        && abs(candidate.frame.minY - sectionTop) <= tolerance
    }
    wait(
      for: predicate,
      element: element,
      description: description,
      file: file,
      line: line
    )
  }

  private func wait(
    for predicate: NSPredicate,
    element: XCUIElement,
    description: String,
    file: StaticString,
    line: UInt
  ) {
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
    let result = XCTWaiter.wait(for: [expectation], timeout: 5)
    record("\(description): \(result == .completed ? "completed" : "timed out")")
    XCTAssertEqual(
      result,
      .completed,
      "Timed out waiting for \(description).",
      file: file,
      line: line
    )
  }

  private func record(_ action: String) {
    actionTrace.append("\(actionTrace.count + 1). \(action)")
  }

  private func attachment(named name: String, value: String) -> XCTAttachment {
    let attachment = XCTAttachment(string: value)
    attachment.name = name
    attachment.lifetime = .keepAlways
    return attachment
  }
}
