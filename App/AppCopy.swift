struct AppCopy {
  private let copy: BruceCopy

  init(mode: BruceMode) {
    copy = BruceCopy(mode: mode)
  }

  var climateTab: String { text(.climateTab) }
  var energyTab: String { text(.energyTab) }
  var generalSettingsTab: String { text(.generalSettingsTab) }
  var homeAssistantSettingsTab: String { text(.homeAssistantSettingsTab) }
  var fullBruceToggle: String { text(.fullBruceToggle) }
  var fullBruceFooter: String { text(.fullBruceFooter) }
  var iconChangeFailedTitle: String { text(.iconChangeFailedTitle) }
  var iconChangeFailedMessage: String { text(.iconChangeFailedMessage) }
  var dismiss: String { text(.dismiss) }
  var notConnectedTitle: String { text(.notConnectedTitle) }
  var notConnectedDescription: String { text(.notConnectedDescription) }
  var connectHomeAssistant: String { text(.connectHomeAssistant) }

  private func text(_ key: Key) -> String {
    copy.text(key.entry)
  }
}

extension AppCopy {
  fileprivate enum Key {
    case climateTab
    case energyTab
    case generalSettingsTab
    case homeAssistantSettingsTab
    case fullBruceToggle
    case fullBruceFooter
    case iconChangeFailedTitle
    case iconChangeFailedMessage
    case dismiss
    case notConnectedTitle
    case notConnectedDescription
    case connectHomeAssistant

    var entry: BruceCopy.Entry {
      switch self {
      case .climateTab:
        .localized("app.climateTab")
      case .energyTab:
        .localized("app.energyTab")
      case .generalSettingsTab:
        .localized("app.generalSettingsTab")
      case .homeAssistantSettingsTab:
        .localized("app.homeAssistantSettingsTab")
      case .fullBruceToggle:
        .localized("app.fullBruceToggle")
      case .fullBruceFooter:
        .localized("app.fullBruceFooter")
      case .iconChangeFailedTitle:
        .localized("app.iconChangeFailedTitle")
      case .iconChangeFailedMessage:
        .localized("app.iconChangeFailedMessage")
      case .dismiss:
        .localized("app.dismiss")
      case .notConnectedTitle:
        .localized("app.notConnectedTitle")
      case .notConnectedDescription:
        .localized("app.notConnectedDescription")
      case .connectHomeAssistant:
        .localized("app.connectHomeAssistant")
      }
    }
  }
}
