import SwiftUI
import WidgetKit

struct EnergyWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: EnergyWidgetEntry

  var copy: EnergyWidgetCopy {
    EnergyWidgetCopy(isFullBruce: entry.isFullBruce)
  }

  var palette: EnergyWidgetPalette {
    EnergyWidgetPalette(isFullBruce: entry.isFullBruce)
  }

  @ViewBuilder
  var body: some View {
    switch family {
    #if os(iOS)
      case .accessoryRectangular:
        accessoryContent
    #endif
    case .systemSmall:
      smallContent
    case .systemMedium:
      mediumContent
    case .systemLarge:
      largeContent
    default:
      smallContent
    }
  }

  #if os(iOS)
    private var accessoryContent: some View {
      Group {
        if let snapshot = entry.snapshot {
          let metrics = snapshot.stableMetrics(copy: copy)
          VStack(alignment: .leading, spacing: 2) {
            HStack {
              HStack(spacing: 4) {
                Image(systemName: metrics[0].icon)
                  .accessibilityHidden(true)
                Text(metrics[0].value)
              }
              .font(.headline)
              .accessibilityElement(children: .ignore)
              .accessibilityLabel(metrics[0].accessibilityLabel)
              .accessibilityValue(accessibilityValue(for: metrics[0]))
              Spacer(minLength: 4)
              freshnessLabel(compact: true)
            }
            HStack(spacing: 8) {
              accessoryMetric(metrics[1])
              accessoryMetric(metrics[2])
            }
            .font(.caption2)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
          }
        } else {
          Label(copy.energyUnavailable, systemImage: "bolt.slash")
            .font(.caption)
        }
      }
    }
  #endif

  private var smallContent: some View {
    VStack(alignment: .leading, spacing: 5) {
      header(title: copy.energy)
      if let snapshot = entry.snapshot {
        let metrics = snapshot.stableMetrics(copy: copy)
        HStack(spacing: 8) {
          Image(systemName: metrics[0].icon)
            .font(.title2)
            .foregroundStyle(metrics[0].color)
            .widgetAccentable()
          VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 3) {
              Text(metrics[0].title)
            }
            .font(.caption)
            .foregroundStyle(palette.secondary)
            Text(metrics[0].value)
              .font(.title2.weight(.semibold))
          }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metrics[0].accessibilityLabel)
        .accessibilityValue(accessibilityValue(for: metrics[0]))

        Divider()
        HStack(alignment: .top, spacing: 8) {
          compactMetric(metrics[1])
          compactMetric(metrics[2])
        }
        Spacer(minLength: 0)
        freshnessLabel(compact: true)
      } else {
        unavailableContent
      }
    }
    .foregroundStyle(palette.primary)
  }

  private var mediumContent: some View {
    VStack(alignment: .leading, spacing: 10) {
      header
      if let snapshot = entry.snapshot {
        HStack(alignment: .top, spacing: 14) {
          VStack(spacing: 8) {
            ForEach(snapshot.stableMetrics(copy: copy)) { metric in
              metricRow(metric)
            }
          }
          Divider()
          VStack(spacing: 8) {
            ForEach(snapshot.changingMetrics(copy: copy).prefix(3)) { metric in
              metricRow(metric)
            }
          }
        }
        Spacer(minLength: 0)
        freshnessLabel(compact: false)
      } else {
        unavailableContent
      }
    }
    .foregroundStyle(palette.primary)
  }

  private var largeContent: some View {
    VStack(alignment: .leading, spacing: 8) {
      header
      if let snapshot = entry.snapshot {
        let metrics =
          snapshot.stableMetrics(copy: copy)
          + snapshot.changingMetrics(copy: copy)
        LazyVGrid(
          columns: [GridItem(.flexible()), GridItem(.flexible())],
          spacing: 7
        ) {
          ForEach(metrics) { metric in
            largeMetric(metric)
          }
        }
        Spacer(minLength: 0)
        freshnessLabel(compact: false)
      } else {
        unavailableContent
      }
    }
    .foregroundStyle(palette.primary)
  }

  private var header: some View {
    header(title: copy.energyNow)
  }

  private func header(title: String) -> some View {
    HStack {
      Text(title)
        .font(.headline)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
      Spacer(minLength: 6)
      Button(intent: EnergyWidgetRefreshIntent()) {
        Image(systemName: "arrow.clockwise")
          .font(.caption.weight(.semibold))
          .frame(minWidth: 44, minHeight: 44)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(copy.refresh)
    }
  }

  private func compactMetric(_ metric: EnergyWidgetMetric) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      HStack(spacing: 2) {
        Text(metric.title)
      }
      .font(.caption2)
      .foregroundStyle(palette.secondary)
      .lineLimit(1)
      Text(metric.value)
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(metric.accessibilityLabel)
    .accessibilityValue(accessibilityValue(for: metric))
  }

  private func metricRow(_ metric: EnergyWidgetMetric) -> some View {
    HStack(spacing: 7) {
      Image(systemName: metric.icon)
        .foregroundStyle(metric.color)
        .frame(width: 18)
        .widgetAccentable()
        .accessibilityHidden(true)
      HStack(spacing: 3) {
        Text(metric.title)
      }
      .font(.caption)
      .foregroundStyle(palette.secondary)
      .lineLimit(1)
      Spacer(minLength: 4)
      Text(metric.value)
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(metric.accessibilityLabel)
    .accessibilityValue(accessibilityValue(for: metric))
  }

  private func largeMetric(_ metric: EnergyWidgetMetric) -> some View {
    HStack(spacing: 10) {
      Image(systemName: metric.icon)
        .font(.title3)
        .foregroundStyle(metric.color)
        .widgetAccentable()
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 1) {
        HStack(spacing: 3) {
          Text(metric.title)
        }
        .font(.caption)
        .foregroundStyle(palette.secondary)
        Text(metric.value)
          .font(.headline)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(palette.metricBackground, in: RoundedRectangle(cornerRadius: 12))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(metric.accessibilityLabel)
    .accessibilityValue(accessibilityValue(for: metric))
  }

}

struct EnergyWidgetPalette {
  let isFullBruce: Bool

  var primary: Color {
    isFullBruce ? .white : Color(red: 0.09, green: 0.24, blue: 0.23)
  }

  var secondary: Color {
    primary.opacity(0.76)
  }

  var background: Color {
    isFullBruce
      ? Color(red: 0.00, green: 0.34, blue: 0.25)
      : Color(red: 0.93, green: 0.89, blue: 0.82)
  }

  var metricBackground: Color {
    primary.opacity(0.07)
  }
}
