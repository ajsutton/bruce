import AppIntents

struct GetEVChargerModeIntent: AppIntent {
  static let title: LocalizedStringResource = "Get EV Charger Mode"
  static let description = IntentDescription(
    "Get the EV charger’s selected mode: Off, Smart Charging, or On.")
  static let supportedModes: IntentModes = .background

  @Dependency var service: BruceSiriService

  func perform() async throws -> some IntentResult & ReturnsValue<EVChargerMode> & ProvidesDialog {
    let mode = EVChargerMode(try await service.chargerMode())
    let copy = SiriCopy.current
    return .result(value: mode, dialog: copy.dialog(copy.chargerMode(mode)))
  }
}
