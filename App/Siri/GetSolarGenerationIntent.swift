import AppIntents

struct GetSolarGenerationIntent: AppIntent {
  static let title: LocalizedStringResource = "Get Solar Generation"
  static let description = IntentDescription("Get current solar or PV generation in kilowatts.")
  static let supportedModes: IntentModes = .background

  @Dependency var service: BruceSiriService

  func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
    let value = try await service.solarGeneration()
    let copy = SiriCopy.current
    return .result(value: value, dialog: copy.dialog(copy.solarGeneration(value)))
  }
}
