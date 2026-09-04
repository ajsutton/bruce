import Foundation

struct EnergyWidgetCopy {
  let isFullBruce: Bool
  private let bundle: Bundle

  init(isFullBruce: Bool, bundle: Bundle = .main) {
    self.isFullBruce = isFullBruce
    self.bundle = bundle
  }

  var energy: String { text("widget.energy") }
  var energyNow: String { text("widget.energyNow") }
  var battery: String { text("widget.battery") }
  var costLast24Hours: String { text("widget.costLast24Hours") }
  var earningsLast24Hours: String { text("widget.earningsLast24Hours") }
  var solar: String { text("widget.solar") }
  var usage: String { text("widget.usage") }
  var gridExport: String { text("widget.gridExport") }
  var gridImport: String { text("widget.gridImport") }
  var gridIdle: String { text("widget.gridIdle") }
  var generalPrice: String { text("widget.generalPrice") }
  var feedInPrice: String { text("widget.feedInPrice") }
  var feedInCharge: String { text("widget.feedInCharge") }
  var lastKnown: String { text("widget.lastKnown") }
  var updated: String { text("widget.updated") }
  var upToDate: String { text("widget.upToDate") }
  var unavailable: String { text("homeEnergy.unavailable") }
  var refresh: String { text("homeEnergy.refresh") }
  var energyUnavailable: String { text("widget.energyUnavailable") }
  var openBruceDetails: String { text("widget.openBruceDetails") }

  var batteryAccessibility: String { text("homeEnergy.batteryAccessibility") }
  var costLast24HoursAccessibility: String { text("homeEnergy.costLast24HoursAccessibility") }
  var earningsLast24HoursAccessibility: String {
    text("homeEnergy.feedInEarningsLast24HoursAccessibility")
  }
  var solarAccessibility: String { text("homeEnergy.pvGenerationAccessibility") }
  var usageAccessibility: String { text("homeEnergy.usageAccessibility") }
  var gridExportAccessibility: String { text("homeEnergy.gridExportAccessibility") }
  var gridImportAccessibility: String { text("homeEnergy.gridImportAccessibility") }
  var gridIdleAccessibility: String { text("homeEnergy.gridIdleAccessibility") }
  var generalPriceAccessibility: String { text("homeEnergy.generalPriceAccessibility") }
  var feedInPriceAccessibility: String { text("homeEnergy.feedInPriceAccessibility") }
  var feedInChargeAccessibility: String { text("homeEnergy.feedInChargeAccessibility") }

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
    guard let path = bundle.path(forResource: localization, ofType: "lproj"),
      let bundle = Bundle(path: path)
    else { return .main }
    return bundle
  }
}
