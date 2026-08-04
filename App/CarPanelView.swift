import SwiftUI

struct CarPanelView: View {
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @ObservedObject var chargingStore: HomeAssistantEVChargingStore
  @State private var panelWidth: CGFloat = 0
  @ObservedObject var garageDoorStore: HomeAssistantGarageDoorStore
  let mode: BruceMode
  var showsConnectionProblems = true
  let manageConnection: () -> Void
  let requestRefresh: () -> Void
  var isEmbedded = false

  private var copy: GarageDoorCopy {
    GarageDoorCopy(mode: mode)
  }

  var body: some View {
    Group {
      if isEmbedded {
        panelContent
      } else {
        NavigationStack {
          ScrollView {
            panelContent
          }
          .navigationTitle(copy.navigationTitle)
          #if os(iOS)
            .toolbarTitleDisplayMode(
              dynamicTypeSize.isAccessibilitySize ? .large : .inline
            )
          #else
            .toolbarTitleDisplayMode(.inline)
          #endif
        }
      }
    }
    .background(mode.panelBackgroundColor(for: colorScheme))
    .preferredColorScheme(mode.isFullBruce ? .dark : nil)
  }

  private var panelContent: some View {
    VStack(spacing: BrucePanelLayout.cardSpacing) {
      if chargingStore.mode != nil || !garageDoorStore.doors.isEmpty {
        LazyVGrid(
          columns: carDeviceColumns,
          alignment: .leading,
          spacing: BrucePanelLayout.cardSpacing
        ) {
          if chargingStore.mode != nil {
            HomeAssistantEVChargingCard(
              store: chargingStore,
              mode: mode,
              showsConnectionProblems: showsConnectionProblems,
              manageConnection: manageConnection,
              requestRefresh: requestRefresh
            )
          }

          if !garageDoorStore.doors.isEmpty {
            ForEach(garageDoorStore.doors) { door in
              HomeAssistantGarageDoorCard(
                door: door,
                isLive: garageDoorStore.isLive,
                isRefreshing: garageDoorStore.isRefreshing,
                mode: mode,
                isLightChanging: garageDoorStore.isControlling(
                  .light,
                  for: door.id
                ),
                isLockChanging: garageDoorStore.isControlling(
                  .lock,
                  for: door.id
                ),
                pendingDoorCommand: garageDoorStore.pendingDoorCommands[door.id],
                toggleLight: {
                  Task {
                    await garageDoorStore.toggleLight(for: door)
                  }
                },
                toggleLock: {
                  Task {
                    await garageDoorStore.toggleLock(for: door)
                  }
                },
                sendDoorCommand: { command in
                  Task {
                    await garageDoorStore.send(command, to: door)
                  }
                }
              )
            }
          }
        }
      }

      if chargingStore.mode == nil,
        let problem = chargingStore.problem,
        showsConnectionProblems || problem.isFeatureSpecific
      {
        chargingProblemView(problem)
      }

      if let problem = garageDoorStore.problem,
        showsConnectionProblems || problem.isFeatureSpecific
      {
        garageProblemView(problem)
      }

      if chargingStore.mode == nil,
        garageDoorStore.doors.isEmpty,
        chargingStore.problem == nil,
        garageDoorStore.problem == nil
      {
        carDevicesUnavailableView
      }
    }
    .padding(BrucePanelLayout.contentPadding)
    .frame(maxWidth: BrucePanelLayout.maximumContentWidth)
    .frame(maxWidth: .infinity)
    .onGeometryChange(for: CGFloat.self) { geometry in
      geometry.size.width
    } action: { width in
      panelWidth = width
    }
  }

  private var carDeviceColumns: [GridItem] {
    if dynamicTypeSize.isAccessibilitySize || horizontalSizeClass == .compact
      || availableContentWidth < BrucePanelLayout.carDeviceMinimumWidth
    {
      return [GridItem(.flexible())]
    }
    return [
      GridItem(
        .adaptive(minimum: BrucePanelLayout.carDeviceMinimumWidth),
        spacing: BrucePanelLayout.cardSpacing,
        alignment: .top
      )
    ]
  }

  private var availableContentWidth: CGFloat {
    max(
      min(panelWidth, BrucePanelLayout.maximumContentWidth)
        - (BrucePanelLayout.contentPadding * 2),
      0
    )
  }

  @ViewBuilder
  private var carDevicesUnavailableView: some View {
    if chargingStore.isLoading || garageDoorStore.isLoading
      || !chargingStore.hasCompletedDiscovery
      || !garageDoorStore.hasCompletedDiscovery
    {
      ProgressView(copy.checkingDevices)
        .frame(maxWidth: .infinity, minHeight: 180)
    } else {
      ContentUnavailableView {
        Label(copy.noDevicesTitle, systemImage: "car.side")
      } description: {
        Text(copy.noDevicesDescription)
      }
      .frame(maxWidth: .infinity, minHeight: 180)
    }
  }

  private func garageProblemView(
    _ problem: HomeAssistantGarageDoorStore.Problem
  ) -> some View {
    HStack(spacing: 12) {
      Label(copy.problem(problem), systemImage: "exclamationmark.triangle.fill")
        .font(.footnote)
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)

      if problem.offersRecoveryAction {
        Button(
          problem.needsConnectionManagement ? copy.manage : copy.refresh,
          action: problem.needsConnectionManagement ? manageConnection : requestRefresh
        )
        .frame(minHeight: 44)
      }
    }
    .padding(16)
    .background(.background, in: RoundedRectangle(cornerRadius: 20))
  }

  private func chargingProblemView(
    _ problem: HomeAssistantEVChargingStore.Problem
  ) -> some View {
    let chargingCopy = EVChargingCopy(mode: mode)
    return HStack(spacing: 12) {
      Label(
        chargingCopy.problem(problem),
        systemImage: "exclamationmark.triangle.fill"
      )
      .font(.footnote)
      .foregroundStyle(.primary)
      .frame(maxWidth: .infinity, alignment: .leading)

      if problem.offersRecoveryAction {
        Button(
          problem.needsConnectionManagement
            ? chargingCopy.manage
            : chargingCopy.refresh,
          action: problem.needsConnectionManagement ? manageConnection : requestRefresh
        )
        .frame(minHeight: 44)
      }
    }
    .padding(16)
    .background(.background, in: RoundedRectangle(cornerRadius: 20))
  }
}

#Preview("Car") {
  CarPanelView(
    chargingStore: HomeAssistantEVChargingStore(
      client: PreviewCarEVChargingClient(),
      mode: .smart,
      activity: .connected,
      decision: .preview
    ),
    garageDoorStore: HomeAssistantGarageDoorStore(
      loader: PreviewGarageDoorLoader(),
      doors: [
        HomeAssistantGarageDoorSnapshot(
          id: "cover.garage",
          name: "Garage Door",
          doorState: .closing,
          lightState: .illuminated,
          lockState: .unlocked,
          lightEntityID: "light.garage",
          lockEntityID: "lock.garage",
          supportsStop: true
        )
      ],
      isLive: true
    ),
    mode: .standard,
    manageConnection: {},
    requestRefresh: {}
  )
  .tint(BruceMode.standard.accentColor)
}

#Preview("Car — No Devices") {
  CarPanelView(
    chargingStore: HomeAssistantEVChargingStore(
      client: PreviewCarEVChargingClient(),
      hasCompletedDiscovery: true
    ),
    garageDoorStore: HomeAssistantGarageDoorStore(
      loader: PreviewGarageDoorLoader(),
      hasCompletedDiscovery: true
    ),
    mode: .standard,
    manageConnection: {},
    requestRefresh: {}
  )
  .tint(BruceMode.standard.accentColor)
}

#Preview("Car — Full Bruce") {
  CarPanelView(
    chargingStore: HomeAssistantEVChargingStore(
      client: PreviewCarEVChargingClient()
    ),
    garageDoorStore: HomeAssistantGarageDoorStore(
      loader: PreviewGarageDoorLoader(),
      doors: [
        HomeAssistantGarageDoorSnapshot(
          id: "cover.garage",
          name: "Garage Door",
          doorState: .closing,
          lightState: .off,
          lockState: .locked,
          lightEntityID: "light.garage",
          lockEntityID: "lock.garage",
          supportsStop: true
        )
      ],
      isLive: true
    ),
    mode: .full,
    manageConnection: {},
    requestRefresh: {}
  )
  .tint(BruceMode.full.accentColor)
}

#Preview("Car — EV Only") {
  CarPanelView(
    chargingStore: HomeAssistantEVChargingStore(
      client: PreviewCarEVChargingClient(),
      mode: .smart,
      activity: .connected,
      decision: .preview
    ),
    garageDoorStore: HomeAssistantGarageDoorStore(
      loader: PreviewGarageDoorLoader(),
      hasCompletedDiscovery: true
    ),
    mode: .standard,
    manageConnection: {},
    requestRefresh: {}
  )
  .tint(BruceMode.standard.accentColor)
}

private struct PreviewCarEVChargingClient: HomeAssistantEVCharging {
  func loadEVChargingMode() async throws -> HomeAssistantEVChargingMode {
    .smart
  }

  func setEVChargingMode(
    _ mode: HomeAssistantEVChargingMode
  ) async throws -> HomeAssistantEVChargingMode {
    mode
  }
}

extension HomeAssistantEVChargingDecision {
  fileprivate static let preview = HomeAssistantEVChargingDecision(
    isChargingDesired: false,
    overnightSafeChargingMinutes: 108,
    priceAllowsCharging: true,
    currentPriceDollarsPerKilowattHour: 0.24,
    batteryStateOfCharge: 78
  )
}

private struct PreviewGarageDoorLoader: HomeAssistantGarageDoorLoading {
  func loadGarageDoors() async throws -> [HomeAssistantGarageDoorSnapshot] {
    []
  }
}
