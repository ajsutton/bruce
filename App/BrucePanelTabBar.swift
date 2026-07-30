#if os(iOS)
  import SwiftUI
  import UIKit

  struct BrucePanelTabBar: UIViewRepresentable {
    let selectedPanel: BrucePanel
    let titles: [String]
    let selectPanel: (BrucePanel) -> Void

    func makeCoordinator() -> Coordinator {
      Coordinator(selectPanel: selectPanel)
    }

    func makeUIView(context: Context) -> UITabBar {
      let tabBar = UITabBar()
      tabBar.delegate = context.coordinator
      updateItems(in: tabBar)
      return tabBar
    }

    func updateUIView(_ tabBar: UITabBar, context: Context) {
      context.coordinator.selectPanel = selectPanel
      if tabBar.items?.map({ $0.title ?? "" }) != titles {
        updateItems(in: tabBar)
      }
      guard let selectedTag = BrucePanel.allCases.firstIndex(of: selectedPanel) else {
        return
      }
      let selectedItem = tabBar.items?.first {
        $0.tag == selectedTag
      }
      if tabBar.selectedItem !== selectedItem {
        tabBar.selectedItem = selectedItem
      }
    }

    private func updateItems(in tabBar: UITabBar) {
      tabBar.items = zip(BrucePanel.allCases, titles).enumerated().map { index, pair in
        UITabBarItem(
          title: pair.1,
          image: UIImage(systemName: pair.0.systemImage),
          tag: index
        )
      }
    }

    final class Coordinator: NSObject, UITabBarDelegate {
      var selectPanel: (BrucePanel) -> Void

      init(selectPanel: @escaping (BrucePanel) -> Void) {
        self.selectPanel = selectPanel
      }

      func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        guard BrucePanel.allCases.indices.contains(item.tag) else { return }
        selectPanel(BrucePanel.allCases[item.tag])
      }
    }
  }
#endif
