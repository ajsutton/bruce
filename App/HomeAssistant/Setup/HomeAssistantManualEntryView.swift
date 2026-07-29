import SwiftUI

struct HomeAssistantManualEntryView: View {
  @ObservedObject var store: HomeAssistantSetupStore
  let mode: BruceMode

  private var setupCopy: HomeAssistantSetupCopy {
    HomeAssistantSetupCopy(mode: mode)
  }

  private var authenticationCopy: HomeAssistantAuthenticationCopy {
    HomeAssistantAuthenticationCopy(mode: mode)
  }

  private var interfaceCopy: HomeAssistantInterfaceCopy {
    HomeAssistantInterfaceCopy(mode: mode)
  }

  var body: some View {
    Form {
      Section {
        TextField(
          interfaceCopy.addressField,
          text: Binding(
            get: { store.manualAddress },
            set: { store.updateManualAddress($0) }
          ),
          prompt: Text(verbatim: "https://home.example.com")
        )
        .textContentType(.URL)
        #if os(iOS)
          .textInputAutocapitalization(.never)
          .keyboardType(.URL)
          .autocorrectionDisabled()
        #endif
        .onSubmit {
          store.validateManualAddress()
        }

        if let error = store.manualValidationError {
          Text(authenticationCopy.manualValidationMessage(error))
            .foregroundStyle(.red)
            .accessibilityLabel(
              "\(interfaceCopy.addressErrorPrefix): \(authenticationCopy.manualValidationMessage(error))"
            )
        }
      } footer: {
        Text(interfaceCopy.addressHelp)
      }

      Section {
        Button(interfaceCopy.continueButton) {
          store.validateManualAddress()
        }
        .disabled(store.manualAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        Button(setupCopy.chooseDiscoveredHome) {
          store.showDiscoveredHomes()
        }
      }
    }
    .formStyle(.grouped)
  }

}
