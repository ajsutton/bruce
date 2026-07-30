import SwiftUI

struct BrucePanelsView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @AppStorage(BrucePanel.storageKey) private var selectedPanel = BrucePanel.climate
  @State private var scrollPosition = ScrollPosition(idType: BrucePanel.self)
  @State private var activeScrollRequest: BrucePanelScrollRequest?
  @State private var panelFrames: [BrucePanel: CGRect] = [:]
  @State private var energyPanelHeight: CGFloat = 0
  @ObservedObject var temperatureStore: HomeAssistantTemperatureStore
  @ObservedObject var chargingStore: HomeAssistantEVChargingStore
  @ObservedObject var garageDoorStore: HomeAssistantGarageDoorStore
  @ObservedObject var homeEnergyStore: HomeAssistantHomeEnergyStore
  let mode: BruceMode
  let isConnecting: Bool
  let connectionProblem: HomeAssistantPresentation.ConnectionProblem?
  let serverStatus: HomeAssistantServerStatus
  let manageConnection: () -> Void
  let requestHomeRefresh: () -> Void
  let isRemovingConnection: Bool

  private var copy: AppCopy {
    AppCopy(mode: mode)
  }

  private var connectionBanner: HomeAssistantConnectionBanner? {
    HomeAssistantConnectionBanner(
      presentationProblem: connectionProblem,
      serverStatus: serverStatus
    )
  }

  private var showsServerStatus: Bool {
    isRemovingConnection || isConnecting || serverStatus.phase != .idle
  }

  var body: some View {
    VStack(spacing: 0) {
      if let connectionBanner {
        HomeAssistantConnectionBannerView(
          banner: connectionBanner,
          lastSuccessfulUpdate: serverStatus.lastSuccessfulUpdate,
          mode: mode,
          manageConnection: manageConnection,
          requestRefresh: requestHomeRefresh
        )
      }

      #if os(macOS)
        macOSPanels
      #else
        iOSPanels
      #endif
    }
    .background(mode.panelBackgroundColor(for: colorScheme).ignoresSafeArea())
  }

  private var serverStatusView: some View {
    HomeAssistantServerStatusView(
      mode: mode,
      status: serverStatus,
      isConnecting: isConnecting,
      isRemovingConnection: isRemovingConnection
    )
  }

  #if os(macOS)
    private var macOSPanels: some View {
      NavigationSplitView {
        panelSidebar
          .navigationSplitViewColumnWidth(min: 170, ideal: 190)
          .safeAreaBar(edge: .bottom, alignment: .leading) {
            if connectionBanner == nil, showsServerStatus {
              serverStatusView.padding()
            }
          }
      } detail: {
        panelScrollView
          .navigationTitle(title(for: selectedPanel))
          .toolbarTitleDisplayMode(.inline)
      }
    }

  #else
    @ViewBuilder
    private var iOSPanels: some View {
      if horizontalSizeClass == .regular {
        iPadPanels
      } else {
        compactIOSPanels
      }
    }

    private var compactIOSPanels: some View {
      panelScrollView
        .safeAreaBar(edge: .bottom, spacing: 0) {
          VStack(alignment: .leading, spacing: 8) {
            if connectionBanner == nil, showsServerStatus {
              serverStatusView.padding(.horizontal)
            }
            BrucePanelTabBar(
              selectedPanel: selectedPanel,
              titles: BrucePanel.allCases.map(title),
              selectPanel: requestScroll
            )
            .frame(maxWidth: .infinity)
            .frame(height: 49)
          }
        }
    }

    private var iPadPanels: some View {
      NavigationSplitView {
        panelSidebar
          .safeAreaBar(edge: .bottom, alignment: .leading) {
            if connectionBanner == nil, showsServerStatus {
              serverStatusView.padding()
            }
          }
      } detail: {
        panelScrollView
          .navigationTitle(title(for: selectedPanel))
          .toolbarTitleDisplayMode(.inline)
      }
    }
  #endif

  private var panelSidebar: some View {
    BrucePanelSidebar(
      selectedPanel: selectedPanel,
      titles: BrucePanel.allCases.map(title),
      activePanel: activeScrollRequest?.panel,
      selectPanel: requestScroll
    )
  }

  private var panelScrollView: some View {
    GeometryReader { viewport in
      ScrollView {
        VStack(spacing: 0) {
          panelSection(.climate, viewportHeight: viewport.size.height) {
            HomeAssistantTemperatureView(
              store: temperatureStore,
              mode: mode,
              isConnecting: isConnecting,
              showsConnectionProblems: connectionBanner == nil,
              requestRefresh: requestHomeRefresh,
              isEmbedded: true
            )
          }

          panelSection(.car, viewportHeight: viewport.size.height) {
            CarPanelView(
              chargingStore: chargingStore,
              garageDoorStore: garageDoorStore,
              mode: mode,
              showsConnectionProblems: connectionBanner == nil,
              manageConnection: manageConnection,
              requestRefresh: requestHomeRefresh,
              isEmbedded: true
            )
          }

          panelSection(.energy, viewportHeight: viewport.size.height) {
            EnergyPanelView(
              homeEnergyStore: homeEnergyStore,
              mode: mode,
              showsConnectionProblems: connectionBanner == nil,
              manageConnection: manageConnection,
              requestRefresh: requestHomeRefresh,
              isEmbedded: true
            )
          }

          Color.clear
            .frame(height: max(viewport.size.height - energyPanelHeight, 0))
            .accessibilityHidden(true)
        }
        .scrollTargetLayout()
      }
      .scrollPosition($scrollPosition, anchor: .top)
      .coordinateSpace(name: BrucePanelScrollCoordinateSpace.name)
      .onAppear {
        requestScroll(to: selectedPanel, animated: false)
      }
      .onChange(of: viewport.size.height) { _, height in
        updateSelectedPanel(viewportHeight: height)
      }
      .onScrollPhaseChange { _, newPhase, context in
        guard newPhase == .idle, activeScrollRequest != nil else { return }
        activeScrollRequest = nil
        updateSelectedPanel(viewportHeight: context.geometry.visibleRect.height)
      }
    }
  }

  private func requestScroll(to panel: BrucePanel) {
    requestScroll(to: panel, animated: true)
  }

  private func requestScroll(to panel: BrucePanel, animated: Bool) {
    let request = BrucePanelScrollRequest(panel: panel)
    activeScrollRequest = request
    selectedPanel = panel
    if panelFrames[panel].map({ abs($0.minY) < 1 }) == true {
      activeScrollRequest = nil
      return
    }
    if animated, !reduceMotion {
      withAnimation(.default) {
        scrollPosition.scrollTo(id: panel, anchor: .top)
      }
    } else {
      withAnimation(nil, completionCriteria: .removed) {
        scrollPosition.scrollTo(id: panel, anchor: .top)
      } completion: {
        guard activeScrollRequest == request else { return }
        activeScrollRequest = nil
      }
    }
  }

  private func panelSection<Content: View>(
    _ panel: BrucePanel,
    viewportHeight: CGFloat,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Label(title(for: panel), systemImage: panel.systemImage)
        .font(.title2)
        .fontWeight(.semibold)
        .padding([.horizontal, .top])
        .accessibilityHeading(.unspecified)

      content()
    }
    .id(panel)
    .onGeometryChange(for: CGRect.self) { geometry in
      geometry.frame(in: .named(BrucePanelScrollCoordinateSpace.name))
    } action: { frame in
      panelFrames[panel] = frame
      if panel == .energy {
        energyPanelHeight = frame.height
      }
      updateSelectedPanel(viewportHeight: viewportHeight)
    }
  }

  private func title(for panel: BrucePanel) -> String {
    switch panel {
    case .climate:
      copy.climateTab
    case .car:
      copy.carTab
    case .energy:
      copy.energyTab
    }
  }

  private func updateSelectedPanel(viewportHeight: CGFloat) {
    guard
      activeScrollRequest == nil,
      let mostVisiblePanel = BrucePanelVisibility.mostVisiblePanel(
        in: panelFrames,
        viewportHeight: viewportHeight
      ),
      mostVisiblePanel != selectedPanel
    else {
      return
    }
    selectedPanel = mostVisiblePanel
  }

}

#Preview("Panels") {
  BrucePanelsPreview.view
}

private enum BrucePanelsPreview {
  @MainActor
  static var view: some View {
    let store = HomeAssistantTemperatureStore(loader: BrucePanelsPreviewLoader())
    let chargingStore = HomeAssistantEVChargingStore(
      client: BrucePanelsPreviewEVChargingClient(),
      mode: .smart
    )
    let homeEnergyStore = HomeAssistantHomeEnergyStore(
      loader: BrucePanelsPreviewHomeEnergyLoader(),
      snapshot: HomeAssistantHomeEnergySnapshot(
        pvPowerKilowatts: 8.4,
        batteryStateOfCharge: 76,
        homeConsumptionKilowatts: 3.1,
        gridPowerKilowatts: -2.7,
        generalPriceDollarsPerKilowattHour: 0.341,
        feedInPriceDollarsPerKilowattHour: 0.127
      ),
      isLive: true
    )
    let garageDoorStore = HomeAssistantGarageDoorStore(
      loader: BrucePanelsPreviewGarageDoorLoader(),
      doors: [
        HomeAssistantGarageDoorSnapshot(
          id: "cover.garage",
          name: "Garage Door",
          doorState: .closed,
          lightState: .off,
          lockState: .locked
        )
      ],
      isLive: true
    )
    return BrucePanelsView(
      temperatureStore: store,
      chargingStore: chargingStore,
      garageDoorStore: garageDoorStore,
      homeEnergyStore: homeEnergyStore,
      mode: .standard,
      isConnecting: false,
      connectionProblem: nil,
      serverStatus: HomeAssistantServerStatus(
        phase: .live,
        lastSuccessfulUpdate: .now
      ),
      manageConnection: {},
      requestHomeRefresh: {},
      isRemovingConnection: false
    )
    .tint(BruceMode.standard.accentColor)
    .task {
      await store.load()
    }
  }
}

private struct BrucePanelScrollRequest: Equatable {
  let id = UUID()
  let panel: BrucePanel
}

private enum BrucePanelScrollCoordinateSpace {
  static let name = "bruce-panels-scroll"
}

private struct BrucePanelsPreviewGarageDoorLoader: HomeAssistantGarageDoorLoading {
  func loadGarageDoors() async throws -> [HomeAssistantGarageDoorSnapshot] {
    []
  }
}

private struct BrucePanelsPreviewEVChargingClient: HomeAssistantEVCharging {
  func loadEVChargingMode() async throws -> HomeAssistantEVChargingMode {
    .smart
  }

  func setEVChargingMode(
    _ mode: HomeAssistantEVChargingMode
  ) async throws -> HomeAssistantEVChargingMode {
    mode
  }
}

private struct BrucePanelsPreviewHomeEnergyLoader: HomeAssistantHomeEnergyLoading {
  func loadHomeEnergySnapshot() async throws -> HomeAssistantHomeEnergySnapshot {
    .unavailable
  }
}

private struct BrucePanelsPreviewLoader: HomeAssistantTemperatureLoading {
  func temperatureUpdates() -> AsyncThrowingStream<
    HomeAssistantTemperatureUpdate, any Error
  > {
    AsyncThrowingStream { continuation in
      continuation.yield(
        .live([
          HomeAssistantTemperatureReading(
            id: "climate.living_room",
            name: "Living Room",
            value: 23.4,
            targetValue: 22,
            unit: "°C",
            powerState: .poweredOn,
            kind: .zone,
            operatingMode: .cooling,
            icon: "mdi:sofa"
          )
        ])
      )
      continuation.finish()
    }
  }
}
