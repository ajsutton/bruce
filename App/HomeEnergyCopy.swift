struct HomeEnergyCopy {
  private let copy: BruceCopy

  init(mode: BruceMode) {
    copy = BruceCopy(mode: mode)
  }

  var energyNow: String { text(.energyNow) }
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
  var batteryHistory: String { text(.batteryHistory) }
  var batteryHistoryPeriod: String { text(.batteryHistoryPeriod) }
  var batteryHistoryLoading: String { text(.batteryHistoryLoading) }
  var batteryHistoryLoadFailed: String { text(.batteryHistoryLoadFailed) }
  var batteryHistoryUnavailable: String { text(.batteryHistoryUnavailable) }
  var batteryHistoryTimeAxis: String { text(.batteryHistoryTimeAxis) }
  var batteryHistoryChargeAxis: String { text(.batteryHistoryChargeAxis) }
  var batteryHistorySeries: String { text(.batteryHistorySeries) }
  var flowHistory: String { text(.flowHistory) }
  var flowHistoryPeriod: String { text(.flowHistoryPeriod) }
  var flowHistoryPolarity: String { text(.flowHistoryPolarity) }
  var flowHistoryLoading: String { text(.flowHistoryLoading) }
  var flowHistoryLoadFailed: String { text(.flowHistoryLoadFailed) }
  var flowHistoryUnavailable: String { text(.flowHistoryUnavailable) }
  var flowHistoryTimeAxis: String { text(.flowHistoryTimeAxis) }
  var flowHistoryPowerAxis: String { text(.flowHistoryPowerAxis) }
  var flowHistorySeries: String { text(.flowHistorySeries) }
  var flowPVGeneration: String { text(.flowPVGeneration) }
  var flowHomeUsage: String { text(.flowHomeUsage) }
  var flowGrid: String { text(.flowGrid) }
  var flowBattery: String { text(.flowBattery) }
  var usage: String { text(.usage) }
  var usageUnavailable: String { text(.usageUnavailable) }
  var grid: String { text(.grid) }
  var gridExport: String { text(.gridExport) }
  var gridImport: String { text(.gridImport) }
  var gridIdle: String { text(.gridIdle) }
  var generalPrice: String { text(.generalPrice) }
  var generalPriceUnavailable: String { text(.generalPriceUnavailable) }
  var feedInPrice: String { text(.feedInPrice) }
  var feedInCharge: String { text(.feedInCharge) }
  var feedInPriceUnavailable: String { text(.feedInPriceUnavailable) }
  var priceHistory: String { text(.priceHistory) }
  var priceHistoryPeriod: String { text(.priceHistoryPeriod) }
  var priceHistoryLoading: String { text(.priceHistoryLoading) }
  var priceHistoryLoadFailed: String { text(.priceHistoryLoadFailed) }
  var priceHistoryUnavailable: String { text(.priceHistoryUnavailable) }
  var priceHistoryTimeAxis: String { text(.priceHistoryTimeAxis) }
  var priceHistoryPriceAxis: String { text(.priceHistoryPriceAxis) }
  var priceHistorySeries: String { text(.priceHistorySeries) }
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
  var generalPriceAccessibility: String { text(.generalPriceAccessibility) }
  var generalPriceUnavailableAccessibility: String {
    text(.generalPriceUnavailableAccessibility)
  }
  var feedInPriceAccessibility: String { text(.feedInPriceAccessibility) }
  var feedInChargeAccessibility: String { text(.feedInChargeAccessibility) }
  var feedInPriceUnavailableAccessibility: String {
    text(.feedInPriceUnavailableAccessibility)
  }

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
    case .reconnecting: text(.reconnecting)
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
    case energyNow, manage, refresh, updating, updatingLastKnownStatus, lastKnown, unavailable
    case updatingLastKnown, pvGeneration, pvGenerationUnavailable, battery, batteryUnavailable
    case batteryHistory, batteryHistoryPeriod, batteryHistoryLoading, batteryHistoryLoadFailed
    case batteryHistoryUnavailable
    case batteryHistoryTimeAxis, batteryHistoryChargeAxis, batteryHistorySeries
    case flowHistory, flowHistoryPeriod, flowHistoryPolarity, flowHistoryLoading
    case flowHistoryLoadFailed, flowHistoryUnavailable
    case flowHistoryTimeAxis, flowHistoryPowerAxis, flowHistorySeries
    case flowPVGeneration, flowHomeUsage, flowGrid, flowBattery
    case usage, usageUnavailable, grid, gridExport, gridImport, gridIdle
    case generalPrice, generalPriceUnavailable, feedInPrice, feedInCharge
    case feedInPriceUnavailable
    case priceHistory, priceHistoryPeriod, priceHistoryLoading, priceHistoryLoadFailed
    case priceHistoryUnavailable
    case priceHistoryTimeAxis, priceHistoryPriceAxis, priceHistorySeries
    case pvGenerationAccessibility, pvGenerationUnavailableAccessibility
    case batteryAccessibility, batteryUnavailableAccessibility
    case usageAccessibility, usageUnavailableAccessibility
    case gridAccessibility, gridExportAccessibility, gridImportAccessibility
    case gridIdleAccessibility
    case generalPriceAccessibility, generalPriceUnavailableAccessibility
    case feedInPriceAccessibility, feedInChargeAccessibility
    case feedInPriceUnavailableAccessibility
    case connectionNeedsManagement, connectionUnavailable, reconnecting, signInRequired
    case invalidResponse

    var entry: BruceCopy.Entry {
      switch self {
      case .energyNow: .localized("homeEnergy.energyNow")
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
      case .batteryHistory:
        .localized("homeEnergy.batteryHistory")
      case .batteryHistoryPeriod:
        .localized("homeEnergy.batteryHistoryPeriod")
      case .batteryHistoryLoading:
        .localized("homeEnergy.batteryHistoryLoading")
      case .batteryHistoryLoadFailed:
        .localized("homeEnergy.batteryHistoryLoadFailed")
      case .batteryHistoryUnavailable:
        .localized("homeEnergy.batteryHistoryUnavailable")
      case .batteryHistoryTimeAxis:
        .localized("homeEnergy.batteryHistoryTimeAxis")
      case .batteryHistoryChargeAxis:
        .localized("homeEnergy.batteryHistoryChargeAxis")
      case .batteryHistorySeries:
        .localized("homeEnergy.batteryHistorySeries")
      case .flowHistory:
        .localized("homeEnergy.flowHistory")
      case .flowHistoryPeriod:
        .localized("homeEnergy.flowHistoryPeriod")
      case .flowHistoryPolarity:
        .localized("homeEnergy.flowHistoryPolarity")
      case .flowHistoryLoading:
        .localized("homeEnergy.flowHistoryLoading")
      case .flowHistoryLoadFailed:
        .localized("homeEnergy.flowHistoryLoadFailed")
      case .flowHistoryUnavailable:
        .localized("homeEnergy.flowHistoryUnavailable")
      case .flowHistoryTimeAxis:
        .localized("homeEnergy.flowHistoryTimeAxis")
      case .flowHistoryPowerAxis:
        .localized("homeEnergy.flowHistoryPowerAxis")
      case .flowHistorySeries:
        .localized("homeEnergy.flowHistorySeries")
      case .flowPVGeneration:
        .localized("homeEnergy.flowPVGeneration")
      case .flowHomeUsage:
        .localized("homeEnergy.flowHomeUsage")
      case .flowGrid:
        .localized("homeEnergy.flowGrid")
      case .flowBattery:
        .localized("homeEnergy.flowBattery")
      case .usage: .localized("homeEnergy.usage")
      case .usageUnavailable:
        .localized("homeEnergy.usageUnavailable")
      case .grid: .localized("homeEnergy.grid")
      case .gridExport: .localized("homeEnergy.gridExport")
      case .gridImport: .localized("homeEnergy.gridImport")
      case .gridIdle: .localized("homeEnergy.gridIdle")
      case .generalPrice: .localized("homeEnergy.generalPrice")
      case .generalPriceUnavailable:
        .localized("homeEnergy.generalPriceUnavailable")
      case .feedInPrice: .localized("homeEnergy.feedInPrice")
      case .feedInCharge: .localized("homeEnergy.feedInCharge")
      case .feedInPriceUnavailable:
        .localized("homeEnergy.feedInPriceUnavailable")
      case .priceHistory:
        .localized("homeEnergy.priceHistory")
      case .priceHistoryPeriod:
        .localized("homeEnergy.priceHistoryPeriod")
      case .priceHistoryLoading:
        .localized("homeEnergy.priceHistoryLoading")
      case .priceHistoryLoadFailed:
        .localized("homeEnergy.priceHistoryLoadFailed")
      case .priceHistoryUnavailable:
        .localized("homeEnergy.priceHistoryUnavailable")
      case .priceHistoryTimeAxis:
        .localized("homeEnergy.priceHistoryTimeAxis")
      case .priceHistoryPriceAxis:
        .localized("homeEnergy.priceHistoryPriceAxis")
      case .priceHistorySeries:
        .localized("homeEnergy.priceHistorySeries")
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
      case .generalPriceAccessibility:
        .localized("homeEnergy.generalPriceAccessibility")
      case .generalPriceUnavailableAccessibility:
        .localized("homeEnergy.generalPriceUnavailableAccessibility")
      case .feedInPriceAccessibility:
        .localized("homeEnergy.feedInPriceAccessibility")
      case .feedInChargeAccessibility:
        .localized("homeEnergy.feedInChargeAccessibility")
      case .feedInPriceUnavailableAccessibility:
        .localized("homeEnergy.feedInPriceUnavailableAccessibility")
      case .connectionNeedsManagement:
        .localized("homeEnergy.connectionNeedsManagement")
      case .connectionUnavailable:
        .localized("homeEnergy.connectionUnavailable")
      case .reconnecting:
        .localized("homeEnergy.reconnecting")
      case .signInRequired:
        .localized("homeEnergy.signInRequired")
      case .invalidResponse:
        .localized("homeEnergy.invalidResponse")
      }
    }
  }
}
