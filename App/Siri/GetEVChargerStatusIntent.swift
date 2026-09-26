import AppIntents

struct GetEVChargerStatusIntent: AppIntent {
  static let title: LocalizedStringResource = "Get EV Charger Status"
  static let description = IntentDescription(
    "Check whether the electric vehicle is charging, connected, unplugged, paused, or finished.")
  static let supportedModes: IntentModes = .background

  @Dependency var service: BruceSiriService

  func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
    let activity = try await service.chargerStatus()
    let copy = SiriCopy.current
    let status = copy.chargerStatus(activity)
    return .result(value: status, dialog: copy.dialog(status))
  }
}
