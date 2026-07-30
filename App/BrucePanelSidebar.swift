import SwiftUI

struct BrucePanelSidebar: View {
  let selectedPanel: BrucePanel
  let titles: [String]
  let activePanel: BrucePanel?
  let selectPanel: (BrucePanel) -> Void

  var body: some View {
    List(BrucePanel.allCases, selection: selection) { panel in
      Label(title(for: panel), systemImage: panel.systemImage)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .tag(panel)
        .simultaneousGesture(
          TapGesture().onEnded {
            guard panel == selectedPanel, activePanel != panel else { return }
            selectPanel(panel)
          }
        )
        .accessibilityAction {
          guard activePanel != panel else { return }
          selectPanel(panel)
        }
    }
  }

  private var selection: Binding<BrucePanel?> {
    Binding(
      get: { selectedPanel },
      set: { panel in
        guard let panel else { return }
        selectPanel(panel)
      }
    )
  }

  private func title(for panel: BrucePanel) -> String {
    guard let index = BrucePanel.allCases.firstIndex(of: panel) else {
      return panel.rawValue
    }
    return titles[index]
  }
}
