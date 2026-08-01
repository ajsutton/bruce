import SwiftUI

@main
@MainActor
struct BruceApp: App {
  #if os(iOS)
    @UIApplicationDelegateAdaptor(BruceAppDelegate.self) private var appDelegate
  #endif
  @StateObject private var modeController = BruceModeController()
  @StateObject private var setupStore: HomeAssistantSetupStore
  @StateObject private var temperatureStore: HomeAssistantTemperatureStore
  @StateObject private var chargingStore: HomeAssistantEVChargingStore
  @StateObject private var garageDoorStore: HomeAssistantGarageDoorStore
  @StateObject private var homeEnergyStore: HomeAssistantHomeEnergyStore
  @StateObject private var observationCoordinator: HomeAssistantObservationCoordinator
  #if os(macOS)
    @StateObject private var settingsNavigation = BruceSettingsNavigation()
  #endif

  init() {
    HomeAssistantMaterialDesignIcon.prepare()
    let dependencies = BruceHomeAssistantDependencies()
    _setupStore = StateObject(wrappedValue: dependencies.setupStore)
    _chargingStore = StateObject(wrappedValue: dependencies.chargingStore)
    _garageDoorStore = StateObject(wrappedValue: dependencies.garageDoorStore)
    _homeEnergyStore = StateObject(wrappedValue: dependencies.homeEnergyStore)
    _temperatureStore = StateObject(wrappedValue: dependencies.temperatureStore)
    _observationCoordinator = StateObject(wrappedValue: dependencies.observationCoordinator)
  }

  var body: some Scene {
    WindowGroup("Bruce", id: "main") {
      #if os(macOS)
        ContentView(
          modeController: modeController,
          setupStore: setupStore,
          temperatureStore: temperatureStore,
          chargingStore: chargingStore,
          garageDoorStore: garageDoorStore,
          homeEnergyStore: homeEnergyStore,
          settingsNavigation: settingsNavigation
        )
        .frame(minWidth: BrucePanelLayout.minimumWindowWidth)
        .tint(modeController.mode.accentColor)
        .environmentObject(observationCoordinator)
      #else
        ContentView(
          modeController: modeController,
          setupStore: setupStore,
          temperatureStore: temperatureStore,
          chargingStore: chargingStore,
          garageDoorStore: garageDoorStore,
          homeEnergyStore: homeEnergyStore
        )
        .tint(modeController.mode.accentColor)
        .environmentObject(observationCoordinator)
      #endif
    }
    #if os(macOS)
      .windowResizability(.contentMinSize)
    #endif

    #if os(macOS)
      Settings {
        BruceSettingsView(
          modeController: modeController,
          setupStore: setupStore,
          settingsNavigation: settingsNavigation
        )
        .tint(modeController.mode.accentColor)
      }
    #endif
  }

}
