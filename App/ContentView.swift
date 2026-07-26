import SwiftUI

struct ContentView: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ObservedObject var modeController: BruceModeController

  private var mode: BruceMode {
    modeController.mode
  }

  private var isFullBruce: Binding<Bool> {
    Binding(
      get: { mode.isFullBruce },
      set: { isEnabled in
        Task {
          await modeController.select(isEnabled ? .full : .standard)
        }
      }
    )
  }

  var body: some View {
    GeometryReader { geometry in
      ScrollView {
        VStack(spacing: 28) {
          BruceMark(mode: mode, isCompact: dynamicTypeSize.isAccessibilitySize)

          ContentUnavailableView {
            Label(mode.title, systemImage: "house.fill")
          } description: {
            Text(mode.introduction)
          }

          VStack(spacing: 8) {
            Toggle("Go The Full Bruce", isOn: isFullBruce)
              .toggleStyle(.switch)
              .disabled(modeController.isTransitioning)

            Text(mode.settingDescription)
              .font(.footnote)
              .foregroundStyle(mode.foregroundColor)
          }
          .frame(maxWidth: 320)
        }
        .padding(32)
        .frame(maxWidth: .infinity, minHeight: geometry.size.height)
      }
    }
    .foregroundStyle(mode.foregroundColor)
    .preferredColorScheme(mode.isFullBruce ? .dark : .light)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(mode.backgroundColor)
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

private struct BruceMark: View {
  let mode: BruceMode
  let isCompact: Bool

  var body: some View {
    ZStack(alignment: .bottomTrailing) {
      Text("B")
        .font(
          mode.isFullBruce
            ? .system(size: isCompact ? 56 : 82, weight: .black)
            : .system(size: isCompact ? 56 : 82, design: .serif)
        )
        .tracking(mode.isFullBruce ? -8 : -5)

      Text(mode.isFullBruce ? "!" : "•")
        .font(
          .system(
            size: isCompact ? (mode.isFullBruce ? 28 : 18) : (mode.isFullBruce ? 36 : 24),
            weight: .black
          )
        )
        .foregroundStyle(
          mode.isFullBruce ? Color(red: 0.91, green: 0.27, blue: 0.20) : mode.accentColor
        )
        .offset(x: mode.isFullBruce ? 4 : 0, y: mode.isFullBruce ? -3 : -6)
    }
    .frame(width: isCompact ? 96 : 132, height: isCompact ? 96 : 132)
    .background(
      mode.isFullBruce
        ? Color(red: 0.00, green: 0.34, blue: 0.25) : Color(red: 0.93, green: 0.89, blue: 0.82)
    )
    .clipShape(.rect(cornerRadius: 30))
    .overlay {
      if mode.isFullBruce {
        RoundedRectangle(cornerRadius: 30)
          .stroke(Color.white, lineWidth: 4)
      }
    }
    .accessibilityHidden(true)
  }
}

#Preview("Bruce") {
  ContentView(modeController: BruceModeController())
}
