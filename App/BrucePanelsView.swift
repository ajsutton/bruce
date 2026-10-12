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

      panels
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
  fileprivate var panels: some View {
    TabView(selection: $selectedPanel) {
      Tab(
        title(for: .climate),
        systemImage: BrucePanel.climate.systemImage,
        value: BrucePanel.climate
      ) {
        panel(identifier: BrucePanel.climate.sectionAccessibilityIdentifier) {
          HomeAssistantTemperatureView(
            store: temperatureStore,
            mode: mode,
            isConnecting: isConnecting,
            showsConnectionProblems: connectionBanner == nil,
            requestRefresh: requestHomeRefresh
          )
        }
      }

      Tab(
        title(for: .car),
        systemImage: BrucePanel.car.systemImage,
        value: BrucePanel.car
      ) {
        panel(identifier: BrucePanel.car.sectionAccessibilityIdentifier) {
          CarPanelView(
            chargingStore: chargingStore,
            garageDoorStore: garageDoorStore,
            mode: mode,
            showsConnectionProblems: connectionBanner == nil,
            manageConnection: manageConnection,
            requestRefresh: requestHomeRefresh
          )
        }
      }

      Tab(
        title(for: .energy),
        systemImage: BrucePanel.energy.systemImage,
        value: BrucePanel.energy
      ) {
        panel(identifier: BrucePanel.energy.sectionAccessibilityIdentifier) {
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
    #if os(iOS)
      .tabViewStyle(.sidebarAdaptable)
      .background {
        BrucePanelSwipeGestureView(
          selectedPanel: $selectedPanel,
          exclusionFrames: panelSwipeExclusionFrames
        )
      }
    #endif
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
