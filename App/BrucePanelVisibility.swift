import CoreGraphics

enum BrucePanelVisibility {
  static func mostVisiblePanel(
    in frames: [BrucePanel: CGRect],
    viewportHeight: CGFloat
  ) -> BrucePanel? {
    var result: (panel: BrucePanel, visibleProportion: CGFloat)?

    for panel in BrucePanel.allCases {
      guard let frame = frames[panel] else {
        continue
      }
      let visibleHeight = max(
        0,
        min(frame.maxY, viewportHeight) - max(frame.minY, 0)
      )
      let relevantHeight = min(frame.height, viewportHeight)
      guard relevantHeight > 0 else {
        continue
      }
      let visibleProportion = visibleHeight / relevantHeight
      if visibleProportion > result?.visibleProportion ?? 0 {
        result = (panel, visibleProportion)
      }
    }

    return result?.panel
  }
}
