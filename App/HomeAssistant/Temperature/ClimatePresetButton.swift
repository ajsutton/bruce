import SwiftUI

struct ClimatePresetButton: View {
  let name: String
  let isSelected: Bool
  let isEnabled: Bool
  let tint: Color
  let selectedForegroundColor: Color
  let accessibilityLabel: String
  let action: () -> Void

  var body: some View {
    Group {
      if isSelected {
        button
          .buttonStyle(.borderedProminent)
      } else {
        button
          .buttonStyle(.bordered)
      }
    }
    .controlSize(.regular)
    .tint(tint)
    .foregroundStyle(isSelected ? selectedForegroundColor : tint)
    .frame(minHeight: 44)
    .disabled(!isEnabled)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private var button: some View {
    Button(action: action) {
      Text(name)
        .lineLimit(1)
    }
  }
}
