import SwiftUI

struct BrucePanelsView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @AppStorage(BrucePanel.storageKey) private var selectedPanel = BrucePanel.climate
  @State private var scrollPosition = ScrollPosition(idType: BrucePanel.self)
  @State private var scrollPhase = ScrollPhase.idle
  @State private var scrollCoordinator = BrucePanelScrollCoordinator()
  @State private var panelFrames: [BrucePanel: CGRect] = [:]
  @State private var energyPanelHeight: CGFloat = 0
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
        .safeAreaBar(edge: .top, alignment: .trailing, spacing: 0) {
          iOSServerStatusOverlay
        }
        .safeAreaBar(edge: .bottom, spacing: 0) {
          BrucePanelTabBar(
            selectedPanel: selectedPanel,
            titles: BrucePanel.allCases.map(title),
            selectPanel: requestScroll
          )
          .frame(maxWidth: .infinity)
          .frame(height: 49)
        }
    }

    private var iPadPanels: some View {
      NavigationSplitView {
        panelSidebar
      } detail: {
        panelScrollView
          .safeAreaBar(edge: .top, alignment: .trailing, spacing: 0) {
            iOSServerStatusOverlay
          }
          .navigationTitle(title(for: selectedPanel))
          .toolbarTitleDisplayMode(.inline)
      }
    }

    @ViewBuilder
    private var iOSServerStatusOverlay: some View {
      if connectionBanner == nil, showsServerStatus {
        serverStatusView
          .padding(.vertical, 8)
          .padding(.trailing)
      }
    }
  #endif

  private var panelSidebar: some View {
    BrucePanelSidebar(
      selectedPanel: selectedPanel,
      titles: BrucePanel.allCases.map(title),
      activePanel: scrollCoordinator.activePanel,
      selectPanel: requestScroll
    )
  }

  private var panelScrollView: some View {
    GeometryReader { viewport in
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
        .scrollTargetLayout()
      }
      .background(mode.panelBackgroundColor(for: colorScheme))
      .scrollPosition($scrollPosition, anchor: .top)
      .coordinateSpace(name: BrucePanelScrollCoordinateSpace.name)
      .onAppear {
        guard selectedPanel != .climate else { return }
        let request = scrollCoordinator.activate(from: .climate, to: selectedPanel)
        performScroll(scrollCoordinator.begin(request, animated: false))
      }
      .onChange(of: scrollCoordinator.pendingRequest) { _, request in
        guard let request else { return }
        performScroll(scrollCoordinator.begin(request, animated: true))
      }
      .onChange(of: viewport.size.height) { _, height in
        updateSelectedPanel(viewportHeight: height)
      }
      .onScrollPhaseChange { _, newPhase, context in
        scrollPhase = newPhase
        if newPhase == .tracking || newPhase == .interacting {
          scrollCoordinator.cancel()
        }
        guard newPhase == .idle else { return }
        let viewportHeight = context.geometry.visibleRect.height
        Task { @MainActor in
          await Task.yield()
          guard scrollPhase == .idle else { return }
          scrollCoordinator.cancel()
          updateSelectedPanel(viewportHeight: viewportHeight)
        }
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
        .modifier(
          BruceAccessibilityIdentifierModifier(
            identifier: panel.sectionAccessibilityIdentifier
          )
        )
        .accessibilityHeading(.unspecified)

      content()
    }
    .id(panel)
    .onGeometryChange(for: CGRect.self) { geometry in
      geometry.frame(in: .named(BrucePanelScrollCoordinateSpace.name))
    } action: { frame in
      panelFrames[panel] = frame
      completeScrollStep(panel, frame: frame)
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
      scrollCoordinator.activePanel == nil,
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

extension BrucePanelsView {
  private var showsServerStatus: Bool {
    serverStatus.phase != .idle || isConnecting || isRemovingConnection
  }

  fileprivate func requestScroll(to panel: BrucePanel) {
    let sourcePanel = selectedPanel
    selectedPanel = panel
    scrollCoordinator.request(
      from: sourcePanel,
      to: panel,
      panelIsAtTop: panelFrames[panel].map({ abs($0.minY) < 1 }) == true
    )
  }

  fileprivate func performScroll(_ command: BrucePanelScrollCoordinator.Command?) {
    guard let command else { return }
    if command.animated, !reduceMotion {
      withAnimation(.default) {
        scrollPosition.scrollTo(id: command.panel, anchor: .top)
      }
    } else {
      withAnimation(nil) {
        scrollPosition.scrollTo(id: command.panel, anchor: .top)
      }
    }
  }

  fileprivate func completeScrollStep(_ panel: BrucePanel, frame: CGRect) {
    guard abs(frame.minY) < 1 else { return }
    performScroll(scrollCoordinator.complete(panel))
  }
}

private enum BrucePanelScrollCoordinateSpace {
  static let name = "bruce-panels-scroll"
}
