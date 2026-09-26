import AppIntents

struct GetHomeBatteryLevelIntent: AppIntent {
  static let title: LocalizedStringResource = "siri.battery.title"
  static let description = IntentDescription(
    "siri.battery.description")
  static let supportedModes: IntentModes = .background

  @Dependency var service: BruceSiriService

  func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
    let value = try await service.batteryLevel()
    let copy = SiriCopy.current
    return .result(value: value, dialog: copy.dialog(copy.batteryLevel(value)))
  }
}
