import SwiftUI
import WidgetKit

@main
struct EnergyWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(
      kind: EnergyWidgetKind.value,
      provider: EnergyWidgetProvider()
    ) { entry in
      EnergyWidgetView(entry: entry)
        .privacySensitive(entry.snapshot != nil)
        .containerBackground(for: .widget) {
          EnergyWidgetPalette(isFullBruce: entry.isFullBruce).background
        }
    }
    .configurationDisplayName(LocalizedStringKey("widget.galleryName"))
    .description(LocalizedStringKey("widget.galleryDescription"))
    .supportedFamilies([
      .accessoryRectangular,
      .systemSmall,
      .systemMedium,
      .systemLarge,
    ])
  }
}

#Preview(as: .accessoryRectangular) {
  EnergyWidget()
} timeline: {
  EnergyWidgetEntry.preview
}

#Preview(as: .systemSmall) {
  EnergyWidget()
} timeline: {
  EnergyWidgetEntry.preview
}

#Preview(as: .systemMedium) {
  EnergyWidget()
} timeline: {
  EnergyWidgetEntry.preview
}

#Preview(as: .systemLarge) {
  EnergyWidget()
} timeline: {
  EnergyWidgetEntry.preview
}

#Preview("Full Bruce compact", as: .systemSmall) {
  EnergyWidget()
} timeline: {
  EnergyWidgetEntry.fullBruceEdgePreview
}

#Preview("Full Bruce medium", as: .systemMedium) {
  EnergyWidget()
} timeline: {
  EnergyWidgetEntry.fullBruceEdgePreview
}

#Preview("Partial last known", as: .systemMedium) {
  EnergyWidget()
} timeline: {
  EnergyWidgetEntry.fullBruceEdgePreview
}

#Preview("Last known accessory", as: .accessoryRectangular) {
  EnergyWidget()
} timeline: {
  EnergyWidgetEntry.lastKnownPreview
}

#Preview("Unavailable", as: .systemSmall) {
  EnergyWidget()
} timeline: {
  EnergyWidgetEntry.unavailablePreview
}

#Preview("Full Bruce unavailable", as: .systemSmall) {
  EnergyWidget()
} timeline: {
  EnergyWidgetEntry.fullBruceUnavailablePreview
}

#Preview("Unavailable large", as: .systemLarge) {
  EnergyWidget()
} timeline: {
  EnergyWidgetEntry.unavailablePreview
}
