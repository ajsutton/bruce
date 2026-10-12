import SwiftUI

struct BrucePanelsView: View {
  @Environment(\.colorScheme) private var colorScheme
  @AppStorage(BrucePanel.storageKey) private var selectedPanel = BrucePanel.climate
  #if os(iOS)
    @State private var panelSwipeExclusionFrames: [CGRect] = []
  #endif
  let temperatureStore: HomeAssistantTemperatureStore
  let chargingStore: HomeAssistantEVChargingStore
  let garageDoorStore: HomeAssistantGarageDoorStore
  let homeEnergyStore: HomeAssistantHomeEnergyStore
  let mode: BruceMode
  let isConnecting: Bool
  let connectionProblem: HomeAssistantPresentation.ConnectionProblem?
  let serverStatus: HomeAssistantServerStatus
  let manageConnection: () -> Void
  let requestHomeRefresh: () -> Void
  let isRemovingConnection: Bool

  private var copy: AppCopy { AppCopy(mode: mode) }

  private var connectionBanner: HomeAssistantConnectionBanner? {
    HomeAssistantConnectionBanner(
      presentationProblem: connectionProblem,
      serverStatus: serverStatus
    )
  }

  private var showsServerStatus: Bool {
    serverStatus.phase != .idle || isConnecting || isRemovingConnection
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
        panels
      #endif
      #if os(macOS)
        if connectionBanner == nil, showsServerStatus {
          serverStatusView
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
      #endif
    }
    .background(mode.panelBackgroundColor(for: colorScheme).ignoresSafeArea())
    #if os(iOS)
      .onPreferenceChange(BrucePanelSwipeExclusionPreferenceKey.self) { frames in
        panelSwipeExclusionFrames = frames
      }
    #endif
  }

  private var serverStatusView: some View {
    HomeAssistantServerStatusView(
      mode: mode,
      status: serverStatus,
      isConnecting: isConnecting,
      isRemovingConnection: isRemovingConnection
    )
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
}

extension BrucePanelsView {
  #if os(macOS)
    fileprivate var macOSPanels: some View {
      NavigationSplitView {
        List(
          BrucePanel.allCases,
          selection: Binding<BrucePanel?>(
            get: { selectedPanel },
            set: { panel in
              guard let panel else { return }
              selectedPanel = panel
            }
          )
        ) { panel in
          Label(title(for: panel), systemImage: panel.systemImage)
            .tag(panel)
        }
        .navigationSplitViewColumnWidth(min: 170, ideal: 190)
      } detail: {
        panelContent(for: selectedPanel)
          .id(selectedPanel)
          .navigationTitle(title(for: selectedPanel))
          .toolbarTitleDisplayMode(.inline)
      }
    }
  #endif

  #if os(iOS)
    fileprivate var panels: some View {
      TabView(selection: $selectedPanel) {
        ForEach(BrucePanel.allCases) { panel in
          Tab(title(for: panel), systemImage: panel.systemImage, value: panel) {
            panelContent(for: panel)
          }
        }
      }
      .tabViewStyle(.sidebarAdaptable)
      .background {
        BrucePanelSwipeGestureView(
          selectedPanel: $selectedPanel,
          exclusionFrames: panelSwipeExclusionFrames
        )
      }
    }
  #endif

  @ViewBuilder
  fileprivate func panelContent(for selectedPanel: BrucePanel) -> some View {
    panel(identifier: selectedPanel.sectionAccessibilityIdentifier) {
      switch selectedPanel {
      case .climate:
        HomeAssistantTemperatureView(
          store: temperatureStore,
          mode: mode,
          isConnecting: isConnecting,
          showsConnectionProblems: connectionBanner == nil,
          requestRefresh: requestHomeRefresh
        )
      case .car:
        CarPanelView(
          chargingStore: chargingStore,
          garageDoorStore: garageDoorStore,
          mode: mode,
          showsConnectionProblems: connectionBanner == nil,
          manageConnection: manageConnection,
          requestRefresh: requestHomeRefresh
        )
      case .energy:
        EnergyPanelView(
          homeEnergyStore: homeEnergyStore,
          mode: mode,
          showsConnectionProblems: connectionBanner == nil,
          manageConnection: manageConnection,
          requestRefresh: requestHomeRefresh
        )
      }
    }
  }

  fileprivate func panel<Content: View>(
    identifier: String?,
    @ViewBuilder content: () -> Content
  ) -> some View {
    content()
      .modifier(BruceAccessibilityIdentifierModifier(identifier: identifier))
      #if os(iOS)
        .safeAreaBar(edge: .top, alignment: .trailing, spacing: 0) {
          if connectionBanner == nil, showsServerStatus {
            serverStatusView
            .padding(.vertical, 8)
            .padding(.trailing)
          }
        }
      #endif
  }
}
