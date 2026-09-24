import SwiftUI

struct ClimateHistorySection: View {
  @Environment(\.scenePhase) private var scenePhase
  @SceneStorage("climateHistory.expanded") private var isExpanded = false
  @SceneStorage("climateHistory.hours") private var hours = 12
  @State private var refreshID = UUID()
  let store: ClimateHistoryStore
  let mode: BruceMode
  let unit: String

  private var copy: ClimateHistoryCopy { ClimateHistoryCopy(mode: mode) }

  var body: some View {
    DisclosureGroup(isExpanded: $isExpanded) {
      VStack(alignment: .leading, spacing: 16) {
        Picker(copy.period, selection: $hours) {
          ForEach([1, 6, 12, 24], id: \.self) { hour in
            Text(Duration.seconds(hour * 3600), format: .units(allowed: [.hours], width: .narrow))
              .tag(hour)
          }
        }
        .pickerStyle(.segmented)
        .padding(.top, 12)
        ClimateHistoryContent(store: store, mode: mode, unit: unit) {
          refreshID = UUID()
        }
      }
    } label: {
      Label(copy.title, systemImage: "chart.xyaxis.line")
        .font(.headline)
        .frame(minHeight: 44)
    }
    .padding(16)
    .background(.background, in: RoundedRectangle(cornerRadius: 20))
    .task(
      id: ObservationKey(
        expanded: isExpanded, hours: hours, isBackground: scenePhase == .background,
        refreshID: refreshID)
    ) {
      guard isExpanded, scenePhase != .background else { return }
      await store.observe(hours: hours)
    }
  }

  private struct ObservationKey: Equatable {
    let expanded: Bool
    let hours: Int
    let isBackground: Bool
    let refreshID: UUID
  }
}

private struct ClimateHistoryContent: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ObservedObject var store: ClimateHistoryStore
  let mode: BruceMode
  let unit: String
  let retry: () -> Void
  @State private var selectedZone: ClimateHistoryZone?
  @State private var contentWidth: CGFloat = 0

  private var copy: ClimateHistoryCopy { ClimateHistoryCopy(mode: mode) }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      if store.hasLoadError {
        HStack {
          Text(copy.failed)
          Spacer()
          Button(copy.retry, action: retry)
            .frame(minHeight: 44)
        }
        .font(.callout)
      }
      if let history = store.history, history.hasValues {
        LazyVGrid(columns: columns, spacing: 20) {
          ForEach(ClimateHistoryZone.all) { zone in
            VStack(alignment: .leading, spacing: 8) {
              HStack {
                Text(zone.name).font(.headline)
                Spacer()
                Button {
                  selectedZone = zone
                } label: {
                  Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(zone.name). \(copy.expand)")
              }
              ClimateHistoryChart(
                zone: zone, points: history.points(for: zone), interval: history.interval,
                unit: unit, mode: mode, isStale: store.isStale
              )
              .equatable()
            }
          }
        }
      } else if store.isLoading {
        ClimateHistoryLoadingView(label: copy.loading)
      } else if !store.hasLoadError {
        ContentUnavailableView(copy.unavailable, systemImage: "chart.xyaxis.line")
          .frame(minHeight: 190)
      }
    }
    .onGeometryChange(for: CGFloat.self) {
      $0.size.width
    } action: {
      contentWidth = $0
    }
    .sheet(item: $selectedZone) { zone in
      ClimateHistoryDetail(store: store, zone: zone, mode: mode, unit: unit)
    }
  }

  private var columns: [GridItem] {
    dynamicTypeSize.isAccessibilitySize || contentWidth < 704
      ? [GridItem(.flexible())]
      : [GridItem(.adaptive(minimum: 340), spacing: 24, alignment: .top)]
  }
}

private struct ClimateHistoryDetail: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject var store: ClimateHistoryStore
  let zone: ClimateHistoryZone
  let mode: BruceMode
  let unit: String

  var body: some View {
    NavigationStack {
      ScrollView {
        if let history = store.history {
          ClimateHistoryChart(
            zone: zone, points: history.points(for: zone), interval: history.interval,
            unit: unit, mode: mode, isStale: store.isStale, height: 360
          )
          .equatable()
          .padding()
        } else if store.isLoading {
          ClimateHistoryLoadingView(label: ClimateHistoryCopy(mode: mode).loading)
        } else {
          ContentUnavailableView(
            store.hasLoadError
              ? ClimateHistoryCopy(mode: mode).failed : ClimateHistoryCopy(mode: mode).unavailable,
            systemImage: "chart.xyaxis.line"
          )
        }
      }
      .navigationTitle(zone.name)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(ClimateHistoryCopy(mode: mode).done) { dismiss() }
        }
      }
    }
    #if os(macOS)
      .frame(minWidth: 600, minHeight: 500)
    #endif
  }
}
