import AppIntents

struct GetHomeBatteryLevelIntent: AppIntent {
  static let title: LocalizedStringResource = "Get Home Battery Level"
  static let description = IntentDescription(
    "Get the current home battery state of charge as a percentage.")
  static let supportedModes: IntentModes = .background

  @Dependency var service: BruceSiriService

  func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
    let value = try await service.batteryLevel()
    let copy = SiriCopy.current
    return .result(value: value, dialog: copy.dialog(copy.batteryLevel(value)))
  }
}
