import ImageIO
import SwiftUI

struct OpenClawAgentAvatar: View {
  let agent: OpenClawAgent
  var size: CGFloat = 56
  @State private var thumbnail: CGImage?

  var body: some View {
    Group {
      if let thumbnail {
        Image(decorative: thumbnail, scale: 1).resizable().scaledToFill()
      } else if let value = agent.identity?.avatarUrl,
        let url = URL(string: value), url.scheme == "https"
      {
        AsyncImage(url: url) { image in
          image.resizable().scaledToFill()
        } placeholder: {
          fallback
        }
      } else {
        fallback
      }
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
    .accessibilityHidden(true)
    .task(id: agent.identity?.avatarUrl) {
      thumbnail = nil
      let image = await OpenClawAvatarCache.shared.image(for: agent.identity?.avatarUrl)
      guard !Task.isCancelled else { return }
      thumbnail = image
    }
  }

  private var fallback: some View {
    ZStack {
      Circle().fill(.quaternary)
      Text(agent.identity?.emoji ?? String(agent.displayName.prefix(1)))
        .font(.system(size: size * 0.4, weight: .medium))
    }
  }
}
