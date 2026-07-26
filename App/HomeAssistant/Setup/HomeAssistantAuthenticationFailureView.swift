import SwiftUI

struct HomeAssistantAuthenticationFailureView: View {
  let copy: HomeAssistantCopy
  let failure: HomeAssistantAuthenticationFailure
  @Binding var showsTechnicalDetails: Bool
  let retry: () -> Void
  let chooseAnotherServer: () -> Void

  var body: some View {
    ScrollView {
      ContentUnavailableView {
        Label(
          copy.authenticationTitle(failure.problem),
          systemImage: "exclamationmark.triangle.fill"
        )
      } description: {
        VStack(spacing: 8) {
          Text(copy.authenticationMessage(failure.problem))
          DisclosureGroup(
            "Technical Details",
            isExpanded: $showsTechnicalDetails
          ) {
            Text(failure.diagnostic)
              .font(.caption)
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
          }
        }
      } actions: {
        Button("Try Again", action: retry)
          .buttonStyle(.borderedProminent)

        Button(copy.recoveryChooseAnotherServer, action: chooseAnotherServer)
      }
      .padding()
      .frame(maxWidth: .infinity)
    }
  }
}
