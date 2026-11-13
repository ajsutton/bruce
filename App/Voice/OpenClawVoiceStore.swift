import Combine
import Foundation
import OSLog

/// App-owned call lifetime: dismissing its UI or backgrounding does not end audio.
@MainActor
final class OpenClawVoiceStore: ObservableObject {
  enum Phase: Equatable {
    case idle, loading, signingIn, choosing, connecting, connected, ending, failed
  }

  struct Browser: Identifiable {
    let id = UUID()
    let url: URL
    let isWebsite: Bool
  }

  enum Problem { case connection, microphone, signIn, unavailable }

  @Published private(set) var phase = Phase.idle
  @Published private(set) var agents: [OpenClawAgent] = []
  @Published private(set) var agent: OpenClawAgent?
  @Published private(set) var isMuted = false
  @Published private(set) var problem: Problem?
  @Published var browser: Browser?
  private let client: any OpenClawVoiceServing
  private let systemCall: any OpenClawSystemCalling
  private let makeAudio: () -> any OpenClawAudioCalling
  private var launchedBrowserID: UUID?
  private var pickerPresenters: Set<UUID> = []
  private var audio: (any OpenClawAudioCalling)?
  private var task: Task<Void, Never>?
  private var connectionDeadline: Task<Void, Never>?
  private var browserWaiter: CheckedContinuation<Void, any Error>?
  private var generation = UUID()
  private var returnsToPicker = false
  private let logger = Logger(subsystem: "net.symphonious.bruce", category: "Voice")

  init(
    client: any OpenClawVoiceServing = OpenClawVoiceClient(),
    systemCall: any OpenClawSystemCalling = OpenClawSystemCall(),
    makeAudio: @escaping () -> any OpenClawAudioCalling = { OpenClawAudioCall() }
  ) {
    self.systemCall = systemCall
    self.client = client
    self.makeAudio = makeAudio
    systemCall.onEnd = { [weak self] in self?.end() }
    systemCall.onMute = { [weak self] muted in self?.applyMuted(muted) }
    systemCall.onFailure = { [weak self] in self?.fail(OpenClawVoiceError.disconnected) }
    client.onDisconnect = { [weak self] in self?.fail(OpenClawVoiceError.disconnected) }
  }

  var hasCall: Bool { phase == .connecting || phase == .connected }

  /// All visible Mac sidebars can deliver sign-in URLs; each URL opens once.
  func claimBrowserLaunch(id: UUID) -> Bool {
    guard browser?.id == id, launchedBrowserID != id else { return false }
    launchedBrowserID = id
    return true
  }

  func presentPicker(id: UUID) {
    pickerPresenters.insert(id)
    if phase == .ending, problem == nil { returnsToPicker = true }
  }

  /// Returns true when the final picker has left, including repeated teardown callbacks.
  func removePicker(id: UUID) -> Bool {
    guard pickerPresenters.remove(id) != nil else { return false }
    if pickerPresenters.isEmpty { returnsToPicker = false }
    return pickerPresenters.isEmpty
  }

  func prepare() {
    if phase == .ending {
      if problem == nil { returnsToPicker = true }
      return
    }
    guard phase == .idle || phase == .failed else { return }
    problem = nil
    agents = []
    agent = nil
    phase = .loading
    let generation = generation
    task = Task { [weak self, client] in
      do {
        let agents = try await client.agents { [weak self] url, website in
          guard let self else { throw CancellationError() }
          try await self.signIn(url: url, website: website)
        }
        try Task.checkCancellation()
        guard let self, self.generation == generation else { return }
        self.browser = nil
        self.agents = agents
        self.phase = .choosing
        self.task = nil
      } catch {
        guard !Task.isCancelled, self?.generation == generation else { return }
        self?.fail(error)
      }
    }
  }

  func start(_ agent: OpenClawAgent) {
    guard phase == .choosing, agents.contains(where: { $0.id == agent.id }) else { return }
    self.agent = agent
    isMuted = false
    phase = .connecting
    let audio = makeAudio()
    self.audio = audio
    let generation = generation
    var didConnect = false
    audio.onConnectionChange = { [weak self] state in
      guard let self, self.generation == generation, self.hasCall else { return }
      switch state {
      case .connected:
        self.connectionDeadline?.cancel()
        if !didConnect {
          didConnect = true
          self.client.connected()
          self.systemCall.connected()
        }
        self.phase = .connected
      case .disconnected:
        self.phase = .connecting
        self.setConnectionDeadline(seconds: 10)
      case .failed:
        self.fail(OpenClawVoiceError.disconnected)
      }
    }
    setConnectionDeadline(seconds: 60)
    task = Task { [weak self, client, systemCall] in
      do {
        let offer = try await audio.offer()
        try Task.checkCancellation()
        try await systemCall.start(agent: agent)
        try Task.checkCancellation()
        let answer = try await client.start(agentID: agent.id, offer: offer)
        try Task.checkCancellation()
        try await audio.accept(answer: answer)
      } catch {
        guard !Task.isCancelled, self?.generation == generation else { return }
        self?.fail(error)
      }
    }
  }

  private func setConnectionDeadline(seconds: Double) {
    connectionDeadline?.cancel()
    let generation = generation
    connectionDeadline = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
      guard self?.generation == generation else { return }
      self?.fail(URLError(.timedOut))
    }
  }

  func toggleMute() {
    guard phase == .connected else { return }
    systemCall.setMuted(!isMuted)
  }

  private func applyMuted(_ muted: Bool) {
    guard hasCall else { return }
    isMuted = muted
    audio?.setMuted(muted)
  }

  func end(returnToPicker: Bool = true) {
    if !returnToPicker { returnsToPicker = false }
    stop(problem: nil, returnToPicker: returnToPicker && hasCall && !pickerPresenters.isEmpty)
  }

  func continueSignIn(browserID: UUID) {
    guard browser?.id == browserID, browser?.isWebsite == true, browserWaiter != nil else { return }
    browser = nil
    browserDismissed()
  }

  func browserDismissed() {
    if let waiter = browserWaiter {
      browserWaiter = nil
      waiter.resume()
    } else if phase == .signingIn {
      end()
    }
  }

  private func signIn(url: URL, website: Bool) async throws {
    phase = .signingIn
    browser = Browser(url: url, isWebsite: website)
    if website {
      try await withCheckedThrowingContinuation { browserWaiter = $0 }
    }
    try Task.checkCancellation()
  }

  private func fail(_ error: any Error) {
    logger.error("Voice connection failed: \(String(describing: error), privacy: .private)")
    let problem: Problem
    switch error {
    case OpenClawVoiceError.microphoneDenied: problem = .microphone
    case is CloudflareAccessError, OpenClawVoiceError.signInRequired: problem = .signIn
    case OpenClawVoiceError.unavailable: problem = .unavailable
    default: problem = .connection
    }
    stop(problem: problem)
  }

  private func stop(problem: Problem?, returnToPicker: Bool = false) {
    guard phase != .ending else { return }
    returnsToPicker = returnToPicker
    generation = UUID()
    phase = .ending
    self.problem = problem
    connectionDeadline?.cancel()
    connectionDeadline = nil
    let previous = task
    previous?.cancel()
    browserWaiter?.resume(throwing: CancellationError())
    browserWaiter = nil
    browser = nil
    systemCall.end(failed: problem != nil)
    audio?.close()
    audio = nil
    isMuted = false
    task = Task { [weak self, client] in
      await previous?.value
      do { try await client.close() } catch {
        self?.logger.error("Voice close failed: \(String(describing: error), privacy: .private)")
      }
      guard let self else { return }
      self.phase = problem == nil ? .idle : .failed
      self.task = nil
      if self.returnsToPicker, !self.pickerPresenters.isEmpty { self.prepare() }
    }
  }
}
