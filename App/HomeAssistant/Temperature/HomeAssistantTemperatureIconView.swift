import SwiftUI

struct HomeAssistantTemperatureIconView: View {
  let identifier: String?

  @ViewBuilder
  var body: some View {
    if let glyph = HomeAssistantMaterialDesignIcon.glyph(for: identifier) {
      Text(verbatim: glyph)
        .font(.custom(HomeAssistantMaterialDesignIcon.fontName, fixedSize: 25))
    } else {
      Image(systemName: "thermometer.medium")
        .font(.title2.weight(.semibold))
    }
  }
}
