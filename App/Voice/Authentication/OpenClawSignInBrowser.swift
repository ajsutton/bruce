#if os(iOS)
  import SafariServices
  import SwiftUI

  struct OpenClawSignInBrowser: UIViewControllerRepresentable {
    let url: URL
    let finished: () -> Void

    func makeUIViewController(context: Context) -> SFSafariViewController {
      let controller = SFSafariViewController(url: url)
      controller.delegate = context.coordinator
      return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(finished: finished) }

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
      let finished: () -> Void
      init(finished: @escaping () -> Void) { self.finished = finished }
      func safariViewControllerDidFinish(_ controller: SFSafariViewController) { finished() }
    }
  }
#endif
