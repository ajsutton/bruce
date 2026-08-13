import XCTest

@MainActor
final class BrucePanelsScreen {
  private let application: XCUIApplication
  private(set) var actionTrace: [String] = []
  private(set) var launchArguments: [String] = []
  private(set) var seed = ""

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
    waitForExistence(
      panel(BruceAccessibilityIdentifier.climatePanelSection),
      description: "the Climate panel"
    )
    waitForSelection(tab("Climate"), description: "the Climate tab to be selected")
  }

  func selectEnergy() {
    select(
      tabLabel: "Energy",
      panelIdentifier: BruceAccessibilityIdentifier.energyPanelSection,
      name: "Energy"
    )
  }

  func selectClimate() {
    select(
      tabLabel: "Climate",
      panelIdentifier: BruceAccessibilityIdentifier.climatePanelSection,
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
    tabLabel: String,
    panelIdentifier: String,
    name: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    record("Tap the \(name) tab")
    let targetTab = tab(tabLabel)
    waitForElement(targetTab, description: "the \(name) tab", file: file, line: line)
    targetTab.tap()

    waitForSelection(
      tab(tabLabel),
      description: "the \(name) tab to be selected",
      file: file,
      line: line
    )
    waitForExistence(
      panel(panelIdentifier),
      description: "the \(name) panel",
      file: file,
      line: line
    )
  }

  private func tab(_ label: String) -> XCUIElement {
    application.tabBars.buttons[label]
  }

  private func panel(_ identifier: String) -> XCUIElement {
    application.descendants(matching: .any)[identifier]
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
