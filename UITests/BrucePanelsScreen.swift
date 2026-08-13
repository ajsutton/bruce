import XCTest

@MainActor
final class BrucePanelsScreen {
  enum Panel {
    case climate
    case garage
    case energy
  }

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

  func swipePanelLeft(to panel: Panel) {
    record("Swipe left across panel content")
    swipe(panelSwipeSurface(selectedPanel), towards: .left)
    waitForPanel(panel)
  }

  func swipePanelRight(to panel: Panel) {
    record("Swipe right across panel content")
    swipe(panelSwipeSurface(selectedPanel), towards: .right)
    waitForPanel(panel)
  }

  func scrollClimateVertically() {
    let room = application.staticTexts["Room 4"]
    waitForExistence(room, description: "a visible Climate room")
    let initialMinimumY = room.frame.minY
    record("Scroll vertically within the Climate panel")
    panel(BruceAccessibilityIdentifier.climatePanelSection).swipeUp()
    wait(
      for: NSPredicate { candidate, _ in
        guard let candidate = candidate as? XCUIElement else { return false }
        return candidate.exists && candidate.frame.minY < initialMinimumY
      },
      element: room,
      description: "Climate content to move vertically",
      file: #filePath,
      line: #line
    )
    waitForPanel(.climate)
  }

  func scrollClimatePresetsHorizontally() {
    let presetRow = application.descendants(matching: .any)[
      BruceAccessibilityIdentifier.climatePresetRow
    ]
    waitForElement(presetRow, description: "the climate preset row")
    XCTAssertFalse(presetRow.frame.isEmpty, "The climate preset row must have a usable frame.")
    let visiblePreset = application.buttons["Area 2 climate preset"]
    waitForElement(visiblePreset, description: "a visible climate preset")
    let initialMinimumX = visiblePreset.frame.minX
    record("Scroll horizontally within the climate preset row")
    let start = presetRow.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
    let end = presetRow.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
    start.press(forDuration: 0.05, thenDragTo: end)
    wait(
      for: NSPredicate { candidate, _ in
        guard let candidate = candidate as? XCUIElement else { return false }
        return candidate.exists && candidate.frame.minX < initialMinimumX - 20
      },
      element: visiblePreset,
      description: "the climate presets to move horizontally",
      file: #filePath,
      line: #line
    )
    waitForPanel(.climate)
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

  private var selectedPanel: Panel {
    if tab("Garage").isSelected { return .garage }
    if tab("Energy").isSelected { return .energy }
    return .climate
  }

  private func panelSection(_ panel: Panel) -> XCUIElement {
    switch panel {
    case .climate:
      self.panel(BruceAccessibilityIdentifier.climatePanelSection)
    case .garage:
      self.panel(BruceAccessibilityIdentifier.carPanelSection)
    case .energy:
      self.panel(BruceAccessibilityIdentifier.energyPanelSection)
    }
  }

  private func panelSwipeSurface(_ panel: Panel) -> XCUIElement {
    panelSection(panel)
  }

  private func waitForPanel(
    _ panel: Panel,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let name: String
    switch panel {
    case .climate:
      name = "Climate"
    case .garage:
      name = "Garage"
    case .energy:
      name = "Energy"
    }
    waitForSelection(
      tab(name),
      description: "the \(name) tab to be selected",
      file: file,
      line: line
    )
    waitForExistence(
      panelSection(panel),
      description: "the \(name) panel",
      file: file,
      line: line
    )
  }

  private enum SwipeDirection {
    case left
    case right
  }

  private func swipe(_ element: XCUIElement, towards direction: SwipeDirection) {
    let applicationFrame = application.frame
    let swipeY = min(element.frame.minY + 80, element.frame.maxY - 1)
    let verticalOffset = swipeY / applicationFrame.height
    swipeApplication(towards: direction, atVerticalOffset: verticalOffset)
  }

  private func swipeApplication(
    towards direction: SwipeDirection,
    atVerticalOffset verticalOffset: CGFloat
  ) {
    let startHorizontalOffset: CGFloat
    let endHorizontalOffset: CGFloat
    switch direction {
    case .left:
      startHorizontalOffset = 0.8
      endHorizontalOffset = 0.2
    case .right:
      startHorizontalOffset = 0.2
      endHorizontalOffset = 0.8
    }
    let start = application.coordinate(
      withNormalizedOffset: CGVector(dx: startHorizontalOffset, dy: verticalOffset)
    )
    let end = application.coordinate(
      withNormalizedOffset: CGVector(dx: endHorizontalOffset, dy: verticalOffset)
    )
    start.press(forDuration: 0.05, thenDragTo: end)
  }

  private func panel(_ identifier: String) -> XCUIElement {
    application.descendants(matching: .any)[identifier]
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

extension BrucePanelsScreen {
  private func waitForElement(
    _ element: XCUIElement,
    description: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    wait(
      for: NSPredicate(format: "exists == true AND hittable == true"),
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
}
