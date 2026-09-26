import AppIntents

struct SetEVChargerModeIntent: AppIntent {
  static let title: LocalizedStringResource = "siri.setMode.title"
  static let description = IntentDescription(
    "siri.setMode.description"
  )
  static let supportedModes: IntentModes = .background
  static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

  @Parameter(title: "siri.mode.parameter") var mode: EVChargerMode
  @Dependency var service: BruceSiriService

  static var parameterSummary: some ParameterSummary {
    Summary("Set EV charger mode to \(\.$mode)")
  }

  func perform() async throws -> some IntentResult & ReturnsValue<EVChargerMode> & ProvidesDialog {
    try await service.setChargerMode(mode.homeAssistantMode)
    let copy = SiriCopy.current
    return .result(value: mode, dialog: copy.dialog(copy.chargerMode(mode, didChange: true)))
  }
}
