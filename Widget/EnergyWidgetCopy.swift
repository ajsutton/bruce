import Foundation

struct EnergyWidgetCopy {
  let isFullBruce: Bool

  var energyNow: String { text("widget.energyNow") }
  var battery: String { text("widget.battery") }
  var costToday: String { text("widget.costToday") }
  var earningsToday: String { text("widget.earningsToday") }
  var solar: String { text("widget.solar") }
  var usage: String { text("widget.usage") }
  var gridExport: String { text("widget.gridExport") }
  var gridImport: String { text("widget.gridImport") }
  var gridIdle: String { text("widget.gridIdle") }
  var generalPrice: String { text("widget.generalPrice") }
  var feedInPrice: String { text("widget.feedInPrice") }
  var feedInCharge: String { text("widget.feedInCharge") }
  var lastKnown: String { text("widget.lastKnown") }
  var upToDate: String { text("widget.upToDate") }
  var unavailable: String { text("homeEnergy.unavailable") }
  var refresh: String { text("homeEnergy.refresh") }
  var energyUnavailable: String { text("widget.energyUnavailable") }
  var openBruceDetails: String { text("widget.openBruceDetails") }

  var batteryAccessibility: String { text("homeEnergy.batteryAccessibility") }
  var costTodayAccessibility: String { text("homeEnergy.costTodayAccessibility") }
  var earningsTodayAccessibility: String {
    text("homeEnergy.feedInEarningsTodayAccessibility")
  }
  var solarAccessibility: String { text("homeEnergy.pvGenerationAccessibility") }
  var usageAccessibility: String { text("homeEnergy.usageAccessibility") }
  var gridExportAccessibility: String { text("homeEnergy.gridExportAccessibility") }
  var gridImportAccessibility: String { text("homeEnergy.gridImportAccessibility") }
  var gridIdleAccessibility: String { text("homeEnergy.gridIdleAccessibility") }
  var generalPriceAccessibility: String { text("homeEnergy.generalPriceAccessibility") }
  var feedInPriceAccessibility: String { text("homeEnergy.feedInPriceAccessibility") }
  var feedInChargeAccessibility: String { text("homeEnergy.feedInChargeAccessibility") }

  func minutesAgo(_ minutes: Int) -> String {
    String(format: text("widget.minutesAgo %lld"), locale: locale, Int64(minutes))
  }

  private func text(_ key: String.LocalizationValue) -> String {
    String(
      localized: key,
      table: "Localizable",
      bundle: localizationBundle,
      locale: locale
    )
  }

  private var locale: Locale {
    Locale(identifier: isFullBruce ? "en-AU" : "en")
  }

  private var localizationBundle: Bundle {
    let localization = isFullBruce ? "en-AU" : "en"
    guard let path = Bundle.main.path(forResource: localization, ofType: "lproj"),
      let bundle = Bundle(path: path)
    else { return .main }
    return bundle
  }
}
