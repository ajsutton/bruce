import SwiftUI

struct HomeAssistantManualEntryView: View {
  @ObservedObject var store: HomeAssistantSetupStore
  let copy: HomeAssistantCopy

  var body: some View {
    Form {
      Section {
        TextField(
          "Home Assistant address",
          text: Binding(
            get: { store.manualAddress },
            set: { store.updateManualAddress($0) }
          ),
          prompt: Text("https://home.example.com")
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
          Text(copy.manualValidationMessage(error))
            .foregroundStyle(.red)
            .accessibilityLabel("Address error: \(copy.manualValidationMessage(error))")
        }
      } footer: {
        Text("Enter the base address, not an API or sign-in page.")
      }

      Section {
        Button("Continue") {
          store.validateManualAddress()
        }
        .disabled(store.manualAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        Button(copy.chooseDiscoveredHome) {
          store.showDiscoveredHomes()
        }
      }
    }
    .formStyle(.grouped)
  }

}
