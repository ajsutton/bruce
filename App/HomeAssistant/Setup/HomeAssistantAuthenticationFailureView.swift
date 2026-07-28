import SwiftUI

struct HomeAssistantAuthenticationFailureView: View {
  let mode: BruceMode
  let failure: HomeAssistantAuthenticationFailure
  @Binding var showsTechnicalDetails: Bool
  let retry: () -> Void
  let chooseAnotherServer: () -> Void

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
    ScrollView {
      ContentUnavailableView {
        Label(
          authenticationCopy.authenticationTitle(failure.problem),
          systemImage: "exclamationmark.triangle.fill"
        )
      } description: {
        VStack(spacing: 8) {
          Text(authenticationCopy.authenticationMessage(failure.problem))
          DisclosureGroup(
            interfaceCopy.technicalDetails,
            isExpanded: $showsTechnicalDetails
          ) {
            Text(failure.diagnostic)
              .font(.caption)
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
          }
        }
      } actions: {
        Button(interfaceCopy.retryAuthentication, action: retry)
          .buttonStyle(.borderedProminent)

        Button(setupCopy.recoveryChooseAnotherServer, action: chooseAnotherServer)
      }
      .padding()
      .frame(maxWidth: .infinity)
    }
  }
}
