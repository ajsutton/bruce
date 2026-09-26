import AppIntents

struct SetEVChargerModeIntent: AppIntent {
  static let title: LocalizedStringResource = "Set EV Charger Mode"
  static let description = IntentDescription(
    "Set the EV charger to Off, Smart Charging, or On. On requests charging immediately; the vehicle may still be unplugged or waiting."
  )
  static let supportedModes: IntentModes = .background
  static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

  @Parameter(title: "Mode") var mode: EVChargerMode
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
