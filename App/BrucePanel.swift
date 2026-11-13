enum BrucePanel: String, CaseIterable, Identifiable {
  case climate
  case car
  case energy
  #if os(iOS)
    case voice
  #endif

  static let storageKey = "selectedPanel"

  var id: Self { self }

  var systemImage: String {
    switch self {
    case .climate:
      "thermometer"
    case .car:
      "car"
    case .energy:
      "bolt"
    #if os(iOS)
      case .voice: "waveform"
    #endif
    }
  }

  var sectionAccessibilityIdentifier: String? {
    switch self {
    case .climate:
      BruceAccessibilityIdentifier.climatePanelSection
    case .car:
      BruceAccessibilityIdentifier.carPanelSection
    case .energy:
      BruceAccessibilityIdentifier.energyPanelSection
    #if os(iOS)
      case .voice: nil
    #endif
    }
  }
}
