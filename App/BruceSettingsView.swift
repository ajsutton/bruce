import SwiftUI

#if os(macOS)
  struct BruceSettingsView: View {
    @ObservedObject var modeController: BruceModeController

    private var isFullBruce: Binding<Bool> {
      Binding(
        get: { modeController.mode.isFullBruce },
        set: { isEnabled in
          modeController.requestSelection(isEnabled ? .full : .standard)
        }
      )
    }

    var body: some View {
      Form {
        Section {
          Toggle("Go The Full Bruce", isOn: isFullBruce)
            .disabled(modeController.isTransitioning)
        } footer: {
          Text("Syncs Bruce’s icon, styling and eligible language across your devices.")
        }
      }
      .formStyle(.grouped)
      .frame(width: 440)
      .task {
        await modeController.synchronize()
      }
      .alert(
        "Bruce couldn’t change the app icon",
        isPresented: Binding(
          get: { modeController.appIconErrorMessage != nil },
          set: { isPresented in
            if !isPresented {
              modeController.appIconErrorMessage = nil
            }
          }
        )
      ) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(modeController.appIconErrorMessage ?? "")
      }
    }
  }

  #Preview("Settings") {
    BruceSettingsView(modeController: BruceModeController())
  }
#endif
