import SwiftUI

struct HomeAssistantRestoringView: View {
  @ObservedObject var store: HomeAssistantSetupStore
  let mode: BruceMode
  let requestRemoval: () -> Void

  private var setupCopy: HomeAssistantSetupCopy {
    HomeAssistantSetupCopy(mode: mode)
  }

  private var interfaceCopy: HomeAssistantInterfaceCopy {
    HomeAssistantInterfaceCopy(mode: mode)
  }

  var body: some View {
    if store.isDisconnecting {
      HomeAssistantProgressView(
        title: interfaceCopy.disconnecting,
        detail: interfaceCopy.disconnectingAccessibility
      )
    } else if store.connectionCheckState == .disconnectFailed {
      ContentUnavailableView {
        Label(interfaceCopy.couldNotRemoveConnection, systemImage: "trash.slash")
      } description: {
        Text(interfaceCopy.couldNotRemoveConnectionMessage)
      } actions: {
        Button(interfaceCopy.tryRemovingAgain, role: .destructive, action: requestRemoval)
      }
      .padding()
    } else {
      VStack(spacing: 0) {
        HomeAssistantProgressView(
          title: setupCopy.restoringTitle,
          detail: setupCopy.restoringDetail
        )

        Button(interfaceCopy.removeConnection, role: .destructive, action: requestRemoval)
          .padding()
      }
    }
  }
}
