import AppIntents

struct GetEVChargerModeIntent: AppIntent {
  static let title: LocalizedStringResource = "siri.mode.title"
  static let description = IntentDescription(
    "siri.mode.description")
  static let supportedModes: IntentModes = .background

  @Dependency var service: BruceSiriService

  func perform() async throws -> some IntentResult & ReturnsValue<EVChargerMode> & ProvidesDialog {
    let mode = EVChargerMode(try await service.chargerMode())
    let copy = SiriCopy.current
    return .result(value: mode, dialog: copy.dialog(copy.chargerMode(mode)))
  }
}
