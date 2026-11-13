import Foundation

@MainActor
protocol OpenClawVoiceServing: AnyObject {
  var onDisconnect: (() -> Void)? { get set }
  func agents(signIn: @escaping @MainActor (URL, Bool) async throws -> Void) async throws
    -> [OpenClawAgent]
  func connect(signIn: @escaping @MainActor (URL, Bool) async throws -> Void) async throws
  func start(agentID: String, offer: String) async throws -> String
  func connected()
  func close() async throws
}

@MainActor
final class OpenClawVoiceClient: OpenClawVoiceServing {
  private let gateway = OpenClawGateway()
  private let credentials = OpenClawCredentialStore()
  private var access: CloudflareAccessSession?
  private let talk: OpenClawTalkTransaction

  init() {
    talk = OpenClawTalkTransaction(gateway: gateway)
    gateway.onTalkEvent = { [weak self] event in
      guard let self, self.talk.closes(event) else { return }
      self.onDisconnect?()
    }
  }

  var onDisconnect: (() -> Void)? {
    didSet { gateway.onDisconnect = onDisconnect }
  }

  func agents(signIn: @escaping @MainActor (URL, Bool) async throws -> Void) async throws
    -> [OpenClawAgent]
  {
    try await connect(signIn: signIn)
    defer { gateway.close() }
    struct Roster: Decodable { let agents: [OpenClawAgent] }
    return try await gateway.call("agents.list").decode(Roster.self).agents
  }

  func connect(signIn: @escaping @MainActor (URL, Bool) async throws -> Void) async throws {
    if let access {
      do { try access.validate() } catch { self.access = nil }
    }
    if access == nil { access = try await authenticate(signIn: signIn) }
    guard let access else { throw OpenClawVoiceError.signInRequired }
    do {
      try await gateway.connect(
        access: access, identity: OpenClawDeviceIdentity(credentials: credentials))
      try await talk.reconcile()
    } catch {
      if !Task.isCancelled, !(error is CancellationError) { self.access = nil }
      gateway.close()
      throw error
    }
  }

  func start(agentID: String, offer: String) async throws -> String {
    guard let access else { throw OpenClawVoiceError.signInRequired }
    do {
      return try await talk.start(agentID: agentID, offer: offer, access: access)
    } catch {
      if !Task.isCancelled, !(error is CancellationError) { self.access = nil }
      throw error
    }
  }

  func connected() { talk.connected() }

  func close() async throws {
    defer { gateway.close() }
    try await talk.close()
  }

  private func authenticate(
    signIn: @escaping @MainActor (URL, Bool) async throws -> Void
  ) async throws -> CloudflareAccessSession {
    guard let url = URL(string: "https://bruce.thesuttons.name") else {
      throw CloudflareAccessError.invalidGateway
    }
    var saved: CloudflareAccessSession?
    if let data = try credentials.load("access-session") {
      do {
        let value = try JSONDecoder().decode(CloudflareAccessSession.self, from: data)
        try value.validate()
        if value.origin == (try CloudflareAccessOrigin(url)) { saved = value }
      } catch { saved = nil }
    }
    let client = CloudflareAccessClient()
    if let application = try await client.discover(gatewayURL: url, session: saved) {
      try await signIn(application.origin.url, true)
      let session = try await CloudflareAccessTransfer(client: client).signIn(
        application: application
      ) { url in
        try await signIn(url, false)
      }
      try Task.checkCancellation()
      try credentials.save(JSONEncoder().encode(session), account: "access-session")
      return session
    }
    guard let saved else { throw OpenClawVoiceError.signInRequired }
    return saved
  }
}
