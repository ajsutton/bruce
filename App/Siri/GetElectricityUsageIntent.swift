import AppIntents

struct GetElectricityUsageIntent: AppIntent {
  static let title: LocalizedStringResource = "siri.usage.title"
  static let description = IntentDescription(
    "siri.usage.description")
  static let supportedModes: IntentModes = .background

  @Dependency var service: BruceSiriService

  func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
    let value = try await service.electricityUsage()
    let copy = SiriCopy.current
    return .result(value: value, dialog: copy.dialog(copy.electricityUsage(value)))
  }
}
