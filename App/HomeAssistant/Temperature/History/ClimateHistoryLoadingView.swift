import SwiftUI

struct ClimateHistoryLoadingView: View {
  let label: String
  @State private var showsProgress = false

  var body: some View {
    Group {
      if showsProgress {
        ProgressView(label)
      } else {
        Color.clear.accessibilityLabel(label)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 190)
    .task {
      do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
      showsProgress = true
    }
  }
}
