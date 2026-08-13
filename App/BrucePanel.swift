enum BrucePanel: String, CaseIterable, Identifiable {
  case climate
  case car
  case energy

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
    }
  }

  var sectionAccessibilityIdentifier: String? {
    switch self {
    case .climate:
      BruceAccessibilityIdentifier.climatePanelSection
    case .car:
      nil
    case .energy:
      BruceAccessibilityIdentifier.energyPanelSection
    }
  }
}
