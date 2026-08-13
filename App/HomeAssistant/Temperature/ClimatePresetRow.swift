import SwiftUI

struct ClimatePresetRow: View {
  @Environment(\.colorScheme) private var colorScheme

  let presets: [HomeAssistantClimatePreset]
  let selectedPresetID: HomeAssistantClimatePreset.Identifier?
  let isEnabled: Bool
  let mode: BruceMode
  let apply: (HomeAssistantClimatePreset) -> Void

  private var copy: TemperatureCopy {
    TemperatureCopy(mode: mode)
  }

  var body: some View {
    if !presets.isEmpty {
      Divider()
        .overlay(mode.isFullBruce ? Color.white.opacity(0.22) : .clear)
        .padding(.top, 16)
        .padding(.bottom, 12)

      ScrollView(.horizontal) {
        HStack(spacing: 8) {
          ForEach(presets) { preset in
            ClimatePresetButton(
              name: name(for: preset),
              isSelected: selectedPresetID == preset.id,
              isEnabled: isEnabled,
              tint: presetTint,
              selectedForegroundColor: selectedPresetForegroundColor,
              accessibilityLabel: accessibilityLabel(for: preset)
            ) {
              apply(preset)
            }
          }
        }
      }
      .scrollIndicators(.hidden)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier(BruceAccessibilityIdentifier.climatePresetRow)
      .modifier(BrucePanelSwipeExclusionModifier())
    }
  }

  private var presetTint: Color {
    if mode.isFullBruce {
      return mode.accentColor
    }

    return colorScheme == .dark
      ? Color(red: 0.48, green: 0.86, blue: 0.77)
      : mode.foregroundColor
  }

  private var selectedPresetForegroundColor: Color {
    if mode.isFullBruce {
      return mode.backgroundColor
    }
    if colorScheme == .dark {
      return mode.foregroundColor
    }

    return .white
  }

  private func name(for preset: HomeAssistantClimatePreset) -> String {
    switch preset.id {
    case .all:
      copy.all
    case .label, .floor:
      preset.name
    case .none:
      copy.none
    }
  }

  private func accessibilityLabel(for preset: HomeAssistantClimatePreset) -> String {
    switch preset.id {
    case .all:
      copy.allClimateZones
    case .label, .floor:
      copy.climatePreset(named: preset.name)
    case .none:
      copy.noClimateZones
    }
  }
}
