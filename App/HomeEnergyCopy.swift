struct HomeEnergyCopy {
  private let copy: BruceCopy

  init(mode: BruceMode) {
    copy = BruceCopy(mode: mode)
  }

  var powerNow: String { text(.powerNow) }
  var manage: String { text(.manage) }
  var refresh: String { text(.refresh) }
  var updating: String { text(.updating) }
  var updatingLastKnownStatus: String { text(.updatingLastKnownStatus) }
  var lastKnown: String { text(.lastKnown) }
  var unavailable: String { text(.unavailable) }
  var pvGeneration: String { text(.pvGeneration) }
  var pvGenerationUnavailable: String { text(.pvGenerationUnavailable) }
  var battery: String { text(.battery) }
  var batteryUnavailable: String { text(.batteryUnavailable) }
  var usage: String { text(.usage) }
  var usageUnavailable: String { text(.usageUnavailable) }
  var grid: String { text(.grid) }
  var gridExport: String { text(.gridExport) }
  var gridImport: String { text(.gridImport) }
  var gridIdle: String { text(.gridIdle) }
  var pvGenerationAccessibility: String { text(.pvGenerationAccessibility) }
  var pvGenerationUnavailableAccessibility: String {
    text(.pvGenerationUnavailableAccessibility)
  }
  var batteryAccessibility: String { text(.batteryAccessibility) }
  var batteryUnavailableAccessibility: String { text(.batteryUnavailableAccessibility) }
  var usageAccessibility: String { text(.usageAccessibility) }
  var usageUnavailableAccessibility: String { text(.usageUnavailableAccessibility) }
  var gridAccessibility: String { text(.gridAccessibility) }
  var gridExportAccessibility: String { text(.gridExportAccessibility) }
  var gridImportAccessibility: String { text(.gridImportAccessibility) }
  var gridIdleAccessibility: String { text(.gridIdleAccessibility) }

  func lastKnown(_ value: String) -> String {
    "\(lastKnown): \(value)"
  }

  func updating(lastKnown value: String) -> String {
    text(.updatingLastKnown).replacingOccurrences(of: "%@", with: value)
  }

  func problem(_ problem: HomeAssistantHomeEnergyStore.Problem) -> String {
    switch problem {
    case .connectionNeedsManagement: text(.connectionNeedsManagement)
    case .connectionUnavailable: text(.connectionUnavailable)
    case .signInRequired: text(.signInRequired)
    case .invalidResponse: text(.invalidResponse)
    }
  }

  private func text(_ key: Key) -> String {
    copy.text(key.entry)
  }
}

extension HomeEnergyCopy {
  fileprivate enum Key {
    case powerNow, manage, refresh, updating, updatingLastKnownStatus, lastKnown, unavailable
    case updatingLastKnown, pvGeneration, pvGenerationUnavailable, battery, batteryUnavailable
    case usage, usageUnavailable, grid, gridExport, gridImport, gridIdle
    case pvGenerationAccessibility, pvGenerationUnavailableAccessibility
    case batteryAccessibility, batteryUnavailableAccessibility
    case usageAccessibility, usageUnavailableAccessibility
    case gridAccessibility, gridExportAccessibility, gridImportAccessibility
    case gridIdleAccessibility
    case connectionNeedsManagement, connectionUnavailable, signInRequired, invalidResponse

    var entry: BruceCopy.Entry {
      switch self {
      case .powerNow: .localized("homeEnergy.powerNow")
      case .manage: .localized("homeEnergy.manage")
      case .refresh: .localized("homeEnergy.refresh")
      case .updating: .localized("homeEnergy.updating")
      case .updatingLastKnownStatus:
        .localized("homeEnergy.updatingLastKnownStatus")
      case .lastKnown: .localized("homeEnergy.lastKnown")
      case .unavailable: .localized("homeEnergy.unavailable")
      case .updatingLastKnown:
        .localized("homeEnergy.updatingLastKnown")
      case .pvGeneration: .localized("homeEnergy.pvGeneration")
      case .pvGenerationUnavailable:
        .localized("homeEnergy.pvGenerationUnavailable")
      case .battery: .localized("homeEnergy.battery")
      case .batteryUnavailable:
        .localized("homeEnergy.batteryUnavailable")
      case .usage: .localized("homeEnergy.usage")
      case .usageUnavailable:
        .localized("homeEnergy.usageUnavailable")
      case .grid: .localized("homeEnergy.grid")
      case .gridExport: .localized("homeEnergy.gridExport")
      case .gridImport: .localized("homeEnergy.gridImport")
      case .gridIdle: .localized("homeEnergy.gridIdle")
      case .pvGenerationAccessibility:
        .localized("homeEnergy.pvGenerationAccessibility")
      case .pvGenerationUnavailableAccessibility:
        .localized("homeEnergy.pvGenerationUnavailableAccessibility")
      case .batteryAccessibility:
        .localized("homeEnergy.batteryAccessibility")
      case .batteryUnavailableAccessibility:
        .localized("homeEnergy.batteryUnavailableAccessibility")
      case .usageAccessibility:
        .localized("homeEnergy.usageAccessibility")
      case .usageUnavailableAccessibility:
        .localized("homeEnergy.usageUnavailableAccessibility")
      case .gridAccessibility:
        .localized("homeEnergy.gridAccessibility")
      case .gridExportAccessibility:
        .localized("homeEnergy.gridExportAccessibility")
      case .gridImportAccessibility:
        .localized("homeEnergy.gridImportAccessibility")
      case .gridIdleAccessibility:
        .localized("homeEnergy.gridIdleAccessibility")
      case .connectionNeedsManagement:
        .localized("homeEnergy.connectionNeedsManagement")
      case .connectionUnavailable:
        .localized("homeEnergy.connectionUnavailable")
      case .signInRequired:
        .localized("homeEnergy.signInRequired")
      case .invalidResponse:
        .localized("homeEnergy.invalidResponse")
      }
    }
  }
}
