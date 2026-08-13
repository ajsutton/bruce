#if os(iOS)
  import SwiftUI
  import UIKit

  struct BrucePanelSwipeGestureView: UIViewRepresentable {
    @Binding var selectedPanel: BrucePanel
    let exclusionFrames: [CGRect]

    func makeCoordinator() -> Coordinator {
      Coordinator(selectedPanel: $selectedPanel)
    }

    func makeUIView(context: Context) -> InstallerView {
      let view = InstallerView()
      view.coordinator = context.coordinator
      return view
    }

    func updateUIView(_ uiView: InstallerView, context: Context) {
      context.coordinator.selectedPanel = $selectedPanel
      context.coordinator.exclusionFrames = exclusionFrames
      context.coordinator.installIfPossible(from: uiView)
    }

    static func dismantleUIView(_ uiView: InstallerView, coordinator: Coordinator) {
      coordinator.uninstall()
    }

    final class InstallerView: UIView {
      weak var coordinator: Coordinator?

      override func didMoveToWindow() {
        super.didMoveToWindow()
        coordinator?.installIfPossible(from: self)
      }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
      var selectedPanel: Binding<BrucePanel>
      var exclusionFrames: [CGRect] = []

      private weak var installerView: UIView?
      private weak var installedView: UIView?
      private var recognizers: [UISwipeGestureRecognizer] = []

      init(selectedPanel: Binding<BrucePanel>) {
        self.selectedPanel = selectedPanel
      }

      func installIfPossible(from installerView: UIView) {
        guard let rootView = installerView.window?.rootViewController?.view else { return }
        guard installedView !== rootView else { return }
        uninstall()

        let directions: [UISwipeGestureRecognizer.Direction] = [.left, .right]
        recognizers = directions.map { direction in
          let recognizer = UISwipeGestureRecognizer(target: self, action: #selector(didSwipe(_:)))
          recognizer.direction = direction
          recognizer.cancelsTouchesInView = false
          recognizer.delegate = self
          rootView.addGestureRecognizer(recognizer)
          return recognizer
        }
        installedView = rootView
        self.installerView = installerView
      }

      func uninstall() {
        if let installedView {
          recognizers.forEach(installedView.removeGestureRecognizer)
        }
        recognizers = []
        installerView = nil
        installedView = nil
      }

      func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
      ) -> Bool {
        true
      }

      func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
      ) -> Bool {
        guard let installerView, installerView.bounds.contains(touch.location(in: installerView))
        else {
          return false
        }
        return !exclusionFrames.contains(where: { $0.contains(touch.location(in: nil)) })
          && !touchBeginsInInteractiveHorizontalContent(touch)
      }

      @objc private func didSwipe(_ recognizer: UISwipeGestureRecognizer) {
        let direction: BrucePanelSwipeDirection
        switch recognizer.direction {
        case .left:
          direction = .left
        case .right:
          direction = .right
        default:
          return
        }
        if let destination = BrucePanelSwipeNavigation.destination(
          from: selectedPanel.wrappedValue,
          direction: direction
        ) {
          selectedPanel.wrappedValue = destination
        }
      }

      private func touchBeginsInInteractiveHorizontalContent(_ touch: UITouch) -> Bool {
        var view = touch.view
        while let candidate = view {
          if candidate is UIControl || candidate is UITabBar {
            return true
          }
          if let scrollView = candidate as? UIScrollView,
            scrollView.alwaysBounceHorizontal
              || (scrollView.contentSize.width > scrollView.bounds.width + 1
                && scrollView.contentSize.height <= scrollView.bounds.height + 1)
          {
            return true
          }
          view = candidate.superview
        }
        return false
      }
    }
  }
#endif
