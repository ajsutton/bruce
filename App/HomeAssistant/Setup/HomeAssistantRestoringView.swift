import SwiftUI

struct HomeAssistantRestoringView: View {
  @ObservedObject var store: HomeAssistantSetupStore
  let title: String
  let detail: String
  let requestRemoval: () -> Void

  var body: some View {
    if store.connectionCheckState == .disconnectFailed {
      ContentUnavailableView {
        Label("Couldn’t Remove Connection", systemImage: "trash.slash")
      } description: {
        Text("Bruce couldn’t remove the saved Home Assistant connection.")
      } actions: {
        Button("Try Removing Again", role: .destructive, action: requestRemoval)
      }
      .padding()
    } else {
      VStack(spacing: 0) {
        HomeAssistantProgressView(title: title, detail: detail)

        if store.isDisconnecting {
          ProgressView("Removing connection…")
            .controlSize(.small)
            .padding()
        } else {
          Button("Remove Connection", role: .destructive, action: requestRemoval)
            .padding()
        }
      }
    }
  }
}
