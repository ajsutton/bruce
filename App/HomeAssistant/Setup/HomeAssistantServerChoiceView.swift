import SwiftUI

#if os(iOS)
  import UIKit
#endif

struct HomeAssistantServerChoiceView: View {
  @Environment(\.openURL) private var openURL
  @ObservedObject var store: HomeAssistantSetupStore
  let mode: BruceMode

  private var copy: HomeAssistantSetupCopy {
    HomeAssistantSetupCopy(mode: mode)
  }

  private var interfaceCopy: HomeAssistantInterfaceCopy {
    HomeAssistantInterfaceCopy(mode: mode)
  }

  var body: some View {
    List {
      if let discoveryProblem = store.discoveryProblem {
        Section {
          discoveryProblemView(discoveryProblem)
        }
      }

      if store.discoveryProblem == nil {
        Section {
          if store.instances.isEmpty {
            HStack(spacing: 12) {
              if store.isSearching {
                ProgressView()
                  .controlSize(.small)
              }
              Text(store.isSearching ? copy.searching : copy.noHomesFound)
            }
          } else {
            ForEach(store.instances) { instance in
              Button {
                store.selectInstance(id: instance.id)
              } label: {
                HStack {
                  VStack(alignment: .leading, spacing: 4) {
                    Text(instance.name)
                      .foregroundStyle(.primary)
                    if let detail = instanceDetail(instance) {
                      Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                  }
                  Spacer()
                  if store.selectedInstanceID == instance.id {
                    Image(systemName: "checkmark")
                      .foregroundStyle(.tint)
                      .accessibilityHidden(true)
                  }
                }
                .contentShape(.rect)
              }
              .buttonStyle(.plain)
              .accessibilityValue(
                store.selectedInstanceID == instance.id ? interfaceCopy.selected : ""
              )
            }
          }
        } header: {
          Text(interfaceCopy.homesSection)
        } footer: {
          Text(store.isSearching ? copy.searchingFooter : copy.searchInactive)
        }
      }

      Section {
        if !store.isSearching {
          Button(copy.searchAgain) {
            store.startDiscovery()
          }
        }

        Button(copy.enterAddressManually) {
          store.showManualEntry()
        }
      }
    }
    .safeAreaInset(edge: .bottom) {
      Button(interfaceCopy.continueButton) {
        store.confirmSelectedInstance()
      }
      .buttonStyle(.borderedProminent)
      .disabled(!store.canConfirmSelectedInstance)
      .padding()
      .frame(maxWidth: .infinity)
      .background(.bar)
    }
  }

  @ViewBuilder
  private func discoveryProblemView(_ problem: HomeAssistantSetupStore.DiscoveryProblem)
    -> some View
  {
    switch problem {
    case .permissionDenied:
      VStack(alignment: .leading, spacing: 8) {
        Text(copy.localNetworkAccessOff)
          .font(.headline)
        Text(permissionRecoveryMessage)
        Button(interfaceCopy.openSettings) {
          if let settingsURL {
            openURL(settingsURL)
          }
        }
      }
    case .failed:
      VStack(alignment: .leading, spacing: 8) {
        Text(copy.discoveryFailed)
          .font(.headline)
        Button(interfaceCopy.retryDiscovery) {
          store.startDiscovery()
        }
      }
    }
  }

  private func instanceDetail(_ instance: HomeAssistantInstance) -> String? {
    let address = instance.internalURL ?? instance.externalURL
    if address == nil {
      return interfaceCopy.resolvingAddress
    }
    if instance.internalURL == nil, instance.eligibleExternalURL == nil {
      return interfaceCopy.remoteAccessRequiresHTTPS
    }
    let detail = [address?.host(), instance.version].compactMap(\.self).joined(separator: " · ")
    return detail.isEmpty ? nil : detail
  }

  private var permissionRecoveryMessage: String {
    #if os(iOS)
      interfaceCopy.allowLocalNetworkIOS
    #else
      interfaceCopy.allowLocalNetworkMac
    #endif
  }

  private var settingsURL: URL? {
    #if os(iOS)
      URL(string: UIApplication.openSettingsURLString)
    #else
      URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork"
      )
    #endif
  }
}
