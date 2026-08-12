#if os(iOS)
  import SwiftUI

  struct HomeAssistantSetupPresentationView<SetupContent: View>: View {
    @ObservedObject var store: HomeAssistantSetupStore
    let mode: BruceMode
    let startsInConnectionManagement: Bool
    let reauthenticate: () -> Void
    let setupContent: SetupContent

    init(
      store: HomeAssistantSetupStore,
      mode: BruceMode,
      startsInConnectionManagement: Bool,
      reauthenticate: @escaping () -> Void,
      @ViewBuilder setupContent: () -> SetupContent
    ) {
      self.store = store
      self.mode = mode
      self.startsInConnectionManagement = startsInConnectionManagement
      self.reauthenticate = reauthenticate
      self.setupContent = setupContent()
    }

    @ViewBuilder
    var body: some View {
      if showsConnectionManagement {
        HomeAssistantConnectionManagementView(
          store: store,
          mode: mode,
          reauthenticate: reauthenticate,
          dismissesAfterNavigation: false
        )
      } else {
        setupContent
      }
    }

    private var showsConnectionManagement: Bool {
      guard startsInConnectionManagement else {
        return false
      }
      switch store.step {
      case .configured, .connected, .disconnecting:
        return true
      case .restoring, .restoreFailed, .introduction, .chooseServer, .manualEntry, .confirmation,
        .unencryptedWarning, .onboardingRequired, .readyForAuthentication, .authenticationFailed,
        .cancelled:
        return false
      }
    }
  }
#endif
