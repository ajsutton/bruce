import AppIntents

struct GetElectricityUsageIntent: AppIntent {
  static let title: LocalizedStringResource = "Get Electricity Usage"
  static let description = IntentDescription(
    "Get current home electricity consumption in kilowatts, not accumulated energy usage.")
  static let supportedModes: IntentModes = .background

  @Dependency var service: BruceSiriService

  func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
    let value = try await service.electricityUsage()
    let copy = SiriCopy.current
    return .result(value: value, dialog: copy.dialog(copy.electricityUsage(value)))
  }
}
