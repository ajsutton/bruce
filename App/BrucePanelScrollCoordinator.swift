import Foundation

struct BrucePanelScrollCoordinator {
  struct Request: Equatable {
    let id = UUID()
    let panel: BrucePanel
    let route: [BrucePanel]

    init(from source: BrucePanel, to panel: BrucePanel) {
      self.panel = panel
      guard
        let sourceIndex = BrucePanel.allCases.firstIndex(of: source),
        let destinationIndex = BrucePanel.allCases.firstIndex(of: panel)
      else {
        route = [panel]
        return
      }
      let step = sourceIndex <= destinationIndex ? 1 : -1
      let panels = stride(
        from: sourceIndex + step,
        through: destinationIndex,
        by: step
      ).map { BrucePanel.allCases[$0] }
      route = panels.isEmpty ? [panel] : panels
    }
  }

  struct Command {
    let panel: BrucePanel
    let animated: Bool
  }

  private(set) var pendingRequest: Request?
  private var activeRequest: Request?
  private var activeRoute: [BrucePanel] = []
  private var activeStep: BrucePanel?
  private var activeIsAnimated = false

  var activePanel: BrucePanel? {
    activeRequest?.panel
  }

  mutating func activate(from source: BrucePanel, to panel: BrucePanel) -> Request {
    let request = Request(from: source, to: panel)
    activeRequest = request
    activeRoute = []
    activeStep = nil
    return request
  }

  mutating func request(
    from source: BrucePanel,
    to panel: BrucePanel,
    panelIsAtTop: Bool
  ) {
    let request = activate(from: source, to: panel)
    if source == panel, panelIsAtTop {
      activeRequest = nil
      return
    }
    pendingRequest = request
  }

  mutating func begin(_ request: Request, animated: Bool) -> Command? {
    guard activeRequest == request else { return nil }
    activeRoute = request.route
    activeStep = nil
    activeIsAnimated = animated
    return nextCommand()
  }

  mutating func complete(_ panel: BrucePanel) -> Command? {
    guard activeRequest != nil, activeStep == panel else { return nil }
    activeStep = nil
    if activeRoute.isEmpty {
      activeRequest = nil
      return nil
    }
    return nextCommand()
  }

  mutating func cancel() {
    activeRequest = nil
    activeRoute = []
    activeStep = nil
  }

  private mutating func nextCommand() -> Command? {
    guard activeRequest != nil, !activeRoute.isEmpty else { return nil }
    let panel = activeRoute.removeFirst()
    activeStep = panel
    return Command(panel: panel, animated: activeIsAnimated)
  }
}
