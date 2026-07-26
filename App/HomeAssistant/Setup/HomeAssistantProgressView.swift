import SwiftUI

struct HomeAssistantProgressView: View {
  let title: String
  let detail: String

  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        ProgressView()
          .controlSize(.large)
        Text(title)
          .font(.headline)
        Text(detail)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
      .padding()
      .frame(maxWidth: .infinity)
    }
  }
}
