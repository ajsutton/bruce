import AppIntents

struct EnergyWidgetRefreshIntent: AppIntent {
  static let title = LocalizedStringResource(
    "widget.refreshIntentTitle",
    table: "Localizable"
  )
  static let description = IntentDescription(
    LocalizedStringResource(
      "widget.refreshIntentDescription",
      table: "Localizable"
    )
  )
  static let openAppWhenRun = false

  func perform() async throws -> some IntentResult {
    .result()
  }
}
