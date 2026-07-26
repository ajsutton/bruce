import Foundation

#if os(macOS)
  @MainActor
  final class BruceSettingsNavigation: ObservableObject {
    enum Section: Hashable {
      case general
      case homeAssistant
    }

    @Published var selectedSection: Section = .general

    func showHomeAssistant() {
      selectedSection = .homeAssistant
    }
  }
#endif
