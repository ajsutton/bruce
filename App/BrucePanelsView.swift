import SwiftUI

struct BrucePanelsView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorScheme) private var colorScheme
  @AppStorage(BrucePanel.storageKey) private var selectedPanel = BrucePanel.climate
  @State private var scrollRequest = BrucePanelScrollRequest(panel: .climate)
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

      if connectionBanner == nil, showsServerStatus {
        HomeAssistantServerStatusView(
          mode: mode,
          status: serverStatus,
          isConnecting: isConnecting,
          isRemovingConnection: isRemovingConnection
        )
      }
    }
    .background(mode.panelBackgroundColor(for: colorScheme).ignoresSafeArea())
  }

  #if os(macOS)
    private var macOSPanels: some View {
      NavigationSplitView {
        List(BrucePanel.allCases, selection: sidebarSelection) { panel in
          Label(title(for: panel), systemImage: panel.systemImage)
            .tag(panel)
        }
        .navigationSplitViewColumnWidth(min: 170, ideal: 190)
      } detail: {
        GeometryReader { viewport in
          ScrollViewReader { proxy in
            ScrollView {
              LazyVStack(spacing: 0) {
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
            }
            .coordinateSpace(name: BrucePanelScrollCoordinateSpace.name)
            .onChange(of: scrollRequest) { _, request in
              activeScrollRequest = request
              withAnimation(reduceMotion ? nil : .default) {
                proxy.scrollTo(request.panel, anchor: .top)
              } completion: {
                guard activeScrollRequest == request else { return }
                activeScrollRequest = nil
                updateSelectedPanel(viewportHeight: viewport.size.height)
              }
            }
            .onAppear {
              let request = BrucePanelScrollRequest(panel: selectedPanel)
              activeScrollRequest = request
              withAnimation(nil) {
                proxy.scrollTo(request.panel, anchor: .top)
              } completion: {
                guard activeScrollRequest == request else { return }
                activeScrollRequest = nil
                updateSelectedPanel(viewportHeight: viewport.size.height)
              }
            }
            .onChange(of: viewport.size.height) { _, height in
              updateSelectedPanel(viewportHeight: height)
            }
          }
        }
        .navigationTitle(title(for: selectedPanel))
        .toolbarTitleDisplayMode(.inline)
      }
    }

    private var sidebarSelection: Binding<BrucePanel?> {
      Binding(
        get: { selectedPanel },
        set: { panel in
          guard let panel else { return }
          requestScroll(to: panel)
        }
      )
    }

    private func requestScroll(to panel: BrucePanel) {
      selectedPanel = panel
      scrollRequest = BrucePanelScrollRequest(panel: panel)
    }
  #else
    private var iOSPanels: some View {
      TabView(selection: $selectedPanel) {
        Tab(copy.climateTab, systemImage: "thermometer", value: BrucePanel.climate) {
          HomeAssistantTemperatureView(
            store: temperatureStore,
            mode: mode,
            isConnecting: isConnecting,
            showsConnectionProblems: connectionBanner == nil,
            requestRefresh: requestHomeRefresh
          )
        }

        Tab(copy.carTab, systemImage: "car", value: BrucePanel.car) {
          CarPanelView(
            chargingStore: chargingStore,
            garageDoorStore: garageDoorStore,
            mode: mode,
            showsConnectionProblems: connectionBanner == nil,
            manageConnection: manageConnection,
            requestRefresh: requestHomeRefresh
          )
        }

        Tab(copy.energyTab, systemImage: "bolt", value: BrucePanel.energy) {
          EnergyPanelView(
            homeEnergyStore: homeEnergyStore,
            mode: mode,
            showsConnectionProblems: connectionBanner == nil,
            manageConnection: manageConnection,
            requestRefresh: requestHomeRefresh
          )
        }
      }
      .tabViewStyle(.sidebarAdaptable)
    }
  #endif

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
