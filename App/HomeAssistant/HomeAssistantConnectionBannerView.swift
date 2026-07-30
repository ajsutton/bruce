import SwiftUI

struct HomeAssistantConnectionBannerView: View {
  let banner: HomeAssistantConnectionBanner
  let lastSuccessfulUpdate: Date?
  let mode: BruceMode
  let manageConnection: () -> Void
  let requestRefresh: () -> Void

  private var copy: HomeAssistantInterfaceCopy {
    HomeAssistantInterfaceCopy(mode: mode)
  }

  var body: some View {
    TimelineView(
      .periodic(
        from: HomeAssistantServerStatus.nextTimestampRefresh(
          after: .now,
          lastSuccessfulUpdate: lastSuccessfulUpdate
        ),
        by: 60
      )
    ) { context in
      bannerContent(at: context.date)
    }
  }

  private func bannerContent(at date: Date) -> some View {
    HStack(alignment: .center, spacing: 12) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.red)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 2) {
        Text(copy.connectionBannerProblem(banner.problem))
          .font(.callout)
        if let lastSuccessfulUpdate,
          date.timeIntervalSince(lastSuccessfulUpdate)
            >= HomeAssistantServerStatus.recentUpdateInterval
        {
          lastUpdatedText(lastSuccessfulUpdate)
            .font(.caption)
        }
      }
      .foregroundStyle(foregroundStyle)
      .frame(maxWidth: .infinity, alignment: .leading)

      switch banner.action {
      case .manageConnection:
        Button(copy.manageConnection, action: manageConnection)
          .frame(minWidth: 44, minHeight: 44)
          .accessibilityLabel(copy.manageConnectionAccessibility)
      case .refresh:
        Button(copy.refreshConnection, action: requestRefresh)
          .frame(minWidth: 44, minHeight: 44)
          .accessibilityLabel(copy.refreshConnectionAccessibility)
      case .none:
        EmptyView()
      }
    }
    .padding(.horizontal)
    .padding(.vertical, 8)
    .background(.red.opacity(0.1))
    .accessibilityElement(children: .contain)
  }

  private var foregroundStyle: AnyShapeStyle {
    mode.isFullBruce ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary)
  }

  private func lastUpdatedText(_ date: Date) -> some View {
    HStack(spacing: 4) {
      Text(copy.serverLastChecked)
      Text(
        .currentDate,
        format: Date.AnchoredRelativeFormatStyle(
          anchor: date,
          presentation: .named,
          unitsStyle: .wide
        )
      )
    }
  }
}
