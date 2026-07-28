import SwiftUI

struct HomeAssistantHomeEnergyCard: View {
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ObservedObject var store: HomeAssistantHomeEnergyStore
  let mode: BruceMode
  let manageConnection: () -> Void
  let requestRefresh: () -> Void

  private var copy: HomeEnergyCopy {
    HomeEnergyCopy(mode: mode)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .firstTextBaseline) {
        Text(copy.powerNow)
          .font(.headline)
          .foregroundStyle(primaryForeground)
        Spacer()
        Text(statusText)
          .font(.caption.weight(.medium))
          .foregroundStyle(secondaryForeground)
          .opacity(showsStatus ? 1 : 0)
          .accessibilityHidden(!showsStatus)
      }

      if let problem = store.problem {
        problemView(problem)
      }

      if dynamicTypeSize.isAccessibilitySize {
        VStack(spacing: 12) {
          metricViews
        }
      } else {
        LazyVGrid(
          columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
          ],
          spacing: 12
        ) {
          metricViews
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .background(cardBackground, in: RoundedRectangle(cornerRadius: 20))
    .overlay {
      RoundedRectangle(cornerRadius: 20)
        .stroke(borderColor, lineWidth: 1)
    }
    .shadow(
      color: .black.opacity(mode.isFullBruce ? 0.2 : 0.1),
      radius: 10,
      y: 4
    )
  }

  private func problemView(
    _ problem: HomeAssistantHomeEnergyStore.Problem
  ) -> some View {
    HStack(alignment: .center, spacing: 12) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.red)
          .accessibilityHidden(true)
        Text(copy.problem(problem))
          .font(.footnote)
          .foregroundStyle(primaryForeground)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Button(
        problem.needsConnectionManagement ? copy.manage : copy.refresh,
        action: problem.needsConnectionManagement ? manageConnection : requestRefresh
      )
      .frame(minHeight: 44)
    }
    .accessibilityElement(children: .contain)
  }

  @ViewBuilder
  private var metricViews: some View {
    metric(
      .pv(kilowatts: store.snapshot.pvPowerKilowatts, mode: mode)
    )
    metric(
      .battery(stateOfCharge: store.snapshot.batteryStateOfCharge, mode: mode)
    )
    metric(
      .consumption(kilowatts: store.snapshot.homeConsumptionKilowatts, mode: mode)
    )
    metric(
      .grid(kilowatts: store.snapshot.gridPowerKilowatts, mode: mode)
    )
  }

  private func metric(
    _ presentation: HomeEnergyMetricPresentation
  ) -> some View {
    HStack(spacing: 12) {
      Image(systemName: presentation.icon)
        .font(.title3)
        .foregroundStyle(metricColor(presentation.color))
        .frame(width: 28)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 2) {
        Text(presentation.title)
          .font(.caption)
          .foregroundStyle(secondaryForeground)
        Text(presentation.value)
          .font(.title3.weight(.semibold))
          .foregroundStyle(primaryForeground)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(12)
    .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
    .background(metricBackground, in: RoundedRectangle(cornerRadius: 14))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(presentation.accessibilityLabel)
    .accessibilityValue(accessibilityValue(for: presentation))
  }

  private var statusText: String {
    if store.showsProgress {
      return store.snapshot.hasReadings
        ? copy.updatingLastKnownStatus
        : copy.updating
    }
    return store.snapshot.hasReadings ? copy.lastKnown : copy.unavailable
  }

  private var showsStatus: Bool {
    store.showsProgress || !store.isLive
  }

  private func accessibilityValue(
    for presentation: HomeEnergyMetricPresentation
  ) -> String {
    if store.showsProgress {
      return presentation.value == copy.unavailable
        ? "\(copy.updating). \(copy.unavailable)"
        : copy.updating(lastKnown: presentation.value)
    }
    if store.isLive {
      return presentation.value
    }
    if presentation.value == copy.unavailable {
      return copy.unavailable
    }
    return store.snapshot.hasReadings
      ? copy.lastKnown(presentation.value)
      : copy.unavailable
  }

  private func metricColor(_ color: Color) -> Color {
    store.isLive ? color : .secondary
  }

  private var primaryForeground: AnyShapeStyle {
    mode.isFullBruce ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary)
  }

  private var secondaryForeground: AnyShapeStyle {
    mode.isFullBruce
      ? AnyShapeStyle(Color.white.opacity(0.76))
      : AnyShapeStyle(.secondary)
  }

  private var metricBackground: Color {
    mode.isFullBruce
      ? Color.white.opacity(0.08)
      : mode.foregroundColor.opacity(colorScheme == .dark ? 0.12 : 0.05)
  }

  private var cardBackground: AnyShapeStyle {
    mode.isFullBruce
      ? AnyShapeStyle(Color(red: 0.00, green: 0.25, blue: 0.18))
      : AnyShapeStyle(.background)
  }

  private var borderColor: Color {
    if mode.isFullBruce {
      return mode.accentColor.opacity(0.28)
    }
    return colorScheme == .dark
      ? Color.white.opacity(0.08)
      : mode.foregroundColor.opacity(0.08)
  }
}
