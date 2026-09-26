import AppIntents

struct GetSolarGenerationIntent: AppIntent {
  static let title: LocalizedStringResource = "siri.solar.title"
  static let description = IntentDescription("siri.solar.description")
  static let supportedModes: IntentModes = .background

  @Dependency var service: BruceSiriService

  func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
    let value = try await service.solarGeneration()
    let copy = SiriCopy.current
    return .result(value: value, dialog: copy.dialog(copy.solarGeneration(value)))
  }
}
