import AppIntents

struct GetEVChargerStatusIntent: AppIntent {
  static let title: LocalizedStringResource = "siri.status.title"
  static let description = IntentDescription(
    "siri.status.description")
  static let supportedModes: IntentModes = .background

  @Dependency var service: BruceSiriService

  func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
    let activity = try await service.chargerStatus()
    let copy = SiriCopy.current
    let status = copy.chargerStatus(activity)
    return .result(value: status, dialog: copy.dialog(status))
  }
}
