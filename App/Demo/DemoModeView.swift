import SwiftUI

struct DemoModeView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  @State private var voicePresenterID = UUID()
  @StateObject private var session: DemoSession
  @State private var selectedPanel = BrucePanel.climate
  let mode: BruceMode

  init(mode: BruceMode) {
    self.mode = mode
    _session = StateObject(wrappedValue: DemoSession(mode: mode))
  }

  private var copy: DemoCopy { DemoCopy(mode: mode) }

  var body: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 8) {
        ViewThatFits(in: .horizontal) {
          HStack {
            title
            Spacer()
            exitButton
          }
          VStack(alignment: .leading) {
            title
            exitButton
          }
        }
        Text(copy.disclosure)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        DemoVoiceActions(store: session.voiceStore, session: session, copy: copy)
      }
      .fixedSize(horizontal: false, vertical: true)
      .layoutPriority(1)
      .padding(.horizontal)
      .padding(.bottom, 8)
      Divider()
      BrucePanelsView(
        temperatureStore: session.temperatureStore,
        chargingStore: session.chargingStore,
        garageDoorStore: session.garageDoorStore,
        homeEnergyStore: session.homeEnergyStore,
        mode: mode, isConnecting: false, connectionProblem: nil,
        serverStatus: .idle, manageConnection: {}, requestHomeRefresh: {},
        isRemovingConnection: false,
        selection: $selectedPanel
      )
    }
    .environment(\.bruceVoiceStore, session.voiceStore)
    .tint(mode.accentColor)
    .preferredColorScheme(mode.isFullBruce ? .dark : nil)
    #if os(macOS)
      .frame(minWidth: BrucePanelLayout.minimumWindowWidth, minHeight: 600)
    #endif
    .task { await session.observe() }
    .onDisappear { session.stopVoice() }
    .onChange(of: scenePhase) { _, phase in
      if phase != .active { session.stopVoice() }
    }
    #if os(iOS)
      .onChange(of: selectedPanel, initial: true) { _, panel in
        if panel == .voice {
          session.voiceStore.presentPicker(id: voicePresenterID)
          if session.voiceStore.phase == .idle { session.voiceStore.prepare() }
        } else {
          BruceVoicePresentation.dismissPicker(session.voiceStore, presenterID: voicePresenterID)
        }
      }
    #endif
  }

  private var title: some View {
    Label(copy.title, systemImage: "house").font(.headline)
  }

  private var exitButton: some View {
    Button(copy.exit) { dismiss() }.frame(minHeight: 44)
  }

}

private struct DemoVoiceActions: View {
  @ObservedObject var store: OpenClawVoiceStore
  let session: DemoSession
  let copy: DemoCopy

  var body: some View {
    if store.phase == .connected {
      Menu(copy.sampleQuestions) {
        questions
      }
      .menuStyle(.borderlessButton)
      .frame(minHeight: 44)
      .disabled(store.isMuted)
      if store.isMuted {
        Text(copy.unmuteHint).font(.footnote)
      }
    }
  }

  @ViewBuilder private var questions: some View {
    Button(copy.homeQuestion) { session.describeHome() }
    Button(copy.voiceQuestion) { session.describeVoice() }
    Button(copy.coolLounge) {
      Task { await session.coolLounge() }
    }
  }
}

#Preview("Demo home") {
  DemoModeView(mode: .standard)
}

#Preview("Demo home — large text") {
  DemoModeView(mode: .standard)
    .environment(\.dynamicTypeSize, .accessibility2)
}
