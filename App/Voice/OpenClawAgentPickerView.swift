import SwiftUI

struct OpenClawAgentPickerView: View {
  let agents: [OpenClawAgent]
  let mode: BruceMode
  let select: (OpenClawAgent) -> Void
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Text(VoiceCopy(mode: mode).chooseAgent).font(.headline)
        ForEach(agents) { agent in
          Button {
            select(agent)
          } label: {
            HStack(spacing: 16) {
              OpenClawAgentAvatar(agent: agent)
              Text(agent.displayName).font(.headline).foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
              if !dynamicTypeSize.isAccessibilitySize { Image(systemName: "phone.fill") }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityHint(VoiceCopy(mode: mode).startHint)
        }
      }
    }
  }
}

#Preview("Choose an agent") {
  OpenClawAgentPickerView(
    agents: [
      OpenClawAgent(id: "house", name: "Bruce — House", identity: nil),
      OpenClawAgent(id: "family", name: "Bruce, Brucine & Brucette — Family", identity: nil),
    ], mode: .standard, select: { _ in }
  )
  .padding(20)
  .frame(width: 380, height: 340)
}
