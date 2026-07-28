import SwiftUI

struct HomeAssistantClimateModePicker: View {
  let modes: [HomeAssistantTemperatureReading.ClimateMode]
  let operatingMode: HomeAssistantTemperatureReading.OperatingMode
  let mode: BruceMode
  let isCondensed: Bool
  let select: (HomeAssistantTemperatureReading.ClimateMode) -> Void

  private var copy: TemperatureCopy {
    TemperatureCopy(mode: mode)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(modes, id: \.self) { mode in
        Button {
          select(mode)
        } label: {
          HStack(spacing: 12) {
            Text(mode.label(copy: copy))
            Spacer(minLength: 16)
            Image(systemName: "checkmark")
              .opacity(mode.isCurrent(operatingMode) ? 1 : 0)
              .accessibilityHidden(true)
          }
          .font(modeFont)
          .foregroundStyle(mode.isCurrent(operatingMode) ? Color.accentColor : Color.primary)
          .padding(.horizontal, 12)
          .frame(minHeight: 44)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.accessibilityLabel(copy: copy))
        .accessibilityAddTraits(accessibilityTraits(for: mode))
      }
    }
    .padding(8)
  }

  private var modeFont: Font {
    #if os(macOS)
      if isCondensed {
        return .subheadline.weight(.semibold)
      }
      return .headline
    #else
      if isCondensed {
        return .subheadline.weight(.semibold)
      }
      return .title2.weight(.semibold)
    #endif
  }

  private func accessibilityTraits(
    for mode: HomeAssistantTemperatureReading.ClimateMode
  ) -> AccessibilityTraits {
    var traits: AccessibilityTraits = []
    if mode.isCurrent(operatingMode) {
      _ = traits.insert(.isSelected)
    }
    return traits
  }
}

extension HomeAssistantTemperatureReading.ClimateMode {
  fileprivate func label(copy: TemperatureCopy) -> String {
    switch self {
    case .automatic:
      copy.automatic
    case .cooling:
      copy.cooling
    case .drying:
      copy.drying
    case .fanOnly:
      copy.fanOnly
    case .heating:
      copy.heating
    }
  }

  fileprivate func accessibilityLabel(copy: TemperatureCopy) -> String {
    switch self {
    case .automatic:
      copy.automaticAccessibility
    case .cooling:
      copy.coolingAccessibility
    case .drying:
      copy.dryingAccessibility
    case .fanOnly:
      copy.fanOnlyAccessibility
    case .heating:
      copy.heatingAccessibility
    }
  }

  fileprivate func isCurrent(
    _ operatingMode: HomeAssistantTemperatureReading.OperatingMode
  ) -> Bool {
    switch (self, operatingMode) {
    case (.automatic, .automatic), (.cooling, .cooling), (.drying, .drying),
      (.fanOnly, .fanOnly), (.heating, .heating):
      true
    default:
      false
    }
  }
}

#Preview("Climate Modes") {
  HomeAssistantClimateModePicker(
    modes: [.heating, .cooling, .automatic, .drying, .fanOnly],
    operatingMode: .cooling,
    mode: .full,
    isCondensed: false,
    select: { _ in }
  )
}
