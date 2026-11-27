struct VoiceCopy {
  let mode: BruceMode

  func text(_ key: String.LocalizationValue) -> String {
    BruceCopy(mode: mode).text(.localized(key))
  }

  var agents: String { text("voice.agents") }
  var setupRequired: String { text("voice.setupRequired") }
  var hideCall: String { text("voice.hideCall") }
  var hideCallHint: String { text("voice.hideCallHint") }
  var startHint: String { text("voice.startHint") }
  var openSettings: String { text("voice.openSettings") }
  var privacy: String { text("voice.privacy") }
  var title: String { text("voice.title") }
  var chooseAgent: String { text("voice.chooseAgent") }
  var refreshAgents: String { text("voice.refreshAgents") }
  var loading: String { text("voice.loading") }
  var connecting: String { text("voice.connecting") }
  var connected: String { text("voice.connected") }
  var muted: String { text("voice.muted") }
  var mute: String { text("voice.mute") }
  var unmute: String { text("voice.unmute") }
  var end: String { text("voice.end") }
  var done: String { text("voice.done") }
  var retry: String { text("voice.retry") }
  var logOut: String { text("voice.logOut") }
  var loggedOut: String { text("voice.loggedOut") }
  var loggingOut: String { text("voice.loggingOut") }
  var logoutFailed: String { text("voice.logoutFailed") }
  var logoutExplanation: String { text("voice.logoutExplanation") }
  var signIn: String { text("voice.signIn") }
  var continueSignIn: String { text("voice.continueSignIn") }
  var signInDescription: String { text("voice.signInDescription") }
  var empty: String { text("voice.empty") }
  var failed: String { text("voice.failed") }
  var ending: String { text("voice.ending") }
  var returnToCall: String { text("voice.returnToCall") }

  func message(_ problem: OpenClawVoiceStore.Problem?) -> String {
    switch problem {
    case .microphone: text("voice.microphoneProblem")
    case .signIn: text("voice.signInProblem")
    case .unavailable: text("voice.unavailableProblem")
    case .connection, nil: text("voice.connectionProblem")
    }
  }
}
