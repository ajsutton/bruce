enum BrucePanelSwipeDirection {
  case left
  case right
}

enum BrucePanelSwipeNavigation {
  static func destination(
    from selectedPanel: BrucePanel,
    direction: BrucePanelSwipeDirection
  ) -> BrucePanel? {
    guard let selectedIndex = BrucePanel.allCases.firstIndex(of: selectedPanel) else {
      return nil
    }

    let destinationIndex = selectedIndex + (direction == .left ? 1 : -1)
    guard BrucePanel.allCases.indices.contains(destinationIndex) else {
      return nil
    }
    return BrucePanel.allCases[destinationIndex]
  }
}
