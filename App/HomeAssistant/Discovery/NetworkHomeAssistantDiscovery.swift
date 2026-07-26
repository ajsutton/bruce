import Foundation
import Network
import dnssd

struct BonjourBrowseResult: Sendable {
  let id: String
  let serviceName: String
  let endpoint: NWEndpoint
  let txt: [String: String]
}

enum BonjourBrowserState: Sendable {
  case setup
  case ready
  case waiting(NWError)
  case failed(NWError)
  case cancelled
}

enum BonjourResolverState: Sendable {
  case setup
  case waiting
  case preparing
  case ready
  case failed
  case cancelled
}

protocol BonjourBrowsing: AnyObject, Sendable {
  var stateUpdateHandler: (@Sendable (BonjourBrowserState) -> Void)? { get set }
  var resultsUpdateHandler: (@Sendable ([BonjourBrowseResult]) -> Void)? { get set }
  func start(queue: DispatchQueue)
  func cancel()
}

protocol BonjourResolving: AnyObject, Sendable {
  var stateUpdateHandler: (@Sendable (BonjourResolverState) -> Void)? { get set }
  var remoteEndpoint: NWEndpoint? { get }
  func start(queue: DispatchQueue)
  func cancel()
}

struct NetworkHomeAssistantDiscovery: HomeAssistantDiscoveryBrowsing {
  private let makeBrowser: @Sendable () -> any BonjourBrowsing
  private let makeResolver: @Sendable (NWEndpoint) -> any BonjourResolving

  init(
    makeBrowser: @escaping @Sendable () -> any BonjourBrowsing = {
      NetworkBonjourBrowser()
    },
    makeResolver: @escaping @Sendable (NWEndpoint) -> any BonjourResolving = {
      NetworkBonjourResolver(endpoint: $0)
    }
  ) {
    self.makeBrowser = makeBrowser
    self.makeResolver = makeResolver
  }

  func advertisements()
    -> AsyncThrowingStream<[HomeAssistantDiscoveryAdvertisement], any Error>
  {
    AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
      let session = BrowserSession(
        browser: makeBrowser(),
        makeResolver: makeResolver,
        continuation: continuation
      )
      continuation.onTermination = { @Sendable _ in
        session.cancel()
      }
      session.start()
    }
  }
}

private final class NetworkBonjourBrowser: BonjourBrowsing, @unchecked Sendable {
  var stateUpdateHandler: (@Sendable (BonjourBrowserState) -> Void)?
  var resultsUpdateHandler: (@Sendable ([BonjourBrowseResult]) -> Void)?

  private let browser = NWBrowser(
    for: .bonjourWithTXTRecord(type: "_home-assistant._tcp", domain: "local."),
    using: .tcp
  )

  func start(queue: DispatchQueue) {
    browser.stateUpdateHandler = { [weak self] state in
      self?.stateUpdateHandler?(Self.state(from: state))
    }
    browser.browseResultsChangedHandler = { [weak self] results, _ in
      self?.resultsUpdateHandler?(results.map(Self.result(from:)))
    }
    browser.start(queue: queue)
  }

  func cancel() {
    browser.stateUpdateHandler = nil
    browser.browseResultsChangedHandler = nil
    browser.cancel()
  }

  private static func state(from state: NWBrowser.State) -> BonjourBrowserState {
    switch state {
    case .setup:
      .setup
    case .ready:
      .ready
    case .waiting(let error):
      .waiting(error)
    case .failed(let error):
      .failed(error)
    case .cancelled:
      .cancelled
    @unknown default:
      .cancelled
    }
  }

  private static func result(from result: NWBrowser.Result) -> BonjourBrowseResult {
    let id = result.endpoint.debugDescription
    let serviceName: String
    if case .service(let name, _, _, _) = result.endpoint {
      serviceName = name
    } else {
      serviceName = id
    }
    let txt: [String: String]
    if case .bonjour(let record) = result.metadata {
      txt = record.dictionary
    } else {
      txt = [:]
    }
    return BonjourBrowseResult(
      id: id,
      serviceName: serviceName,
      endpoint: result.endpoint,
      txt: txt
    )
  }
}

private final class NetworkBonjourResolver: BonjourResolving, @unchecked Sendable {
  var stateUpdateHandler: (@Sendable (BonjourResolverState) -> Void)?
  var remoteEndpoint: NWEndpoint? {
    connection.currentPath?.remoteEndpoint
  }

  private let connection: NWConnection

  init(endpoint: NWEndpoint) {
    connection = NWConnection(to: endpoint, using: .tcp)
  }

  func start(queue: DispatchQueue) {
    connection.stateUpdateHandler = { [weak self] state in
      self?.stateUpdateHandler?(Self.state(from: state))
    }
    connection.start(queue: queue)
  }

  func cancel() {
    connection.stateUpdateHandler = nil
    connection.cancel()
  }

  private static func state(from state: NWConnection.State) -> BonjourResolverState {
    switch state {
    case .setup:
      .setup
    case .waiting:
      .waiting
    case .preparing:
      .preparing
    case .ready:
      .ready
    case .failed:
      .failed
    case .cancelled:
      .cancelled
    @unknown default:
      .cancelled
    }
  }
}

private final class BrowserSession: @unchecked Sendable {
  private let queue = DispatchQueue(label: "net.symphonious.bruce.home-assistant-discovery")
  private let browser: any BonjourBrowsing
  private let makeResolver: @Sendable (NWEndpoint) -> any BonjourResolving
  private let continuation:
    AsyncThrowingStream<[HomeAssistantDiscoveryAdvertisement], any Error>.Continuation
  private var advertisements: [String: HomeAssistantDiscoveryAdvertisement] = [:]
  private var resolvers: [String: any BonjourResolving] = [:]
  private var isFinished = false

  init(
    browser: any BonjourBrowsing,
    makeResolver: @escaping @Sendable (NWEndpoint) -> any BonjourResolving,
    continuation: AsyncThrowingStream<
      [HomeAssistantDiscoveryAdvertisement], any Error
    >.Continuation
  ) {
    self.browser = browser
    self.makeResolver = makeResolver
    self.continuation = continuation
  }

  func start() {
    queue.async { [weak self] in
      self?.startOnQueue()
    }
  }

  func cancel() {
    queue.async {
      self.finish()
    }
  }

  private func startOnQueue() {
    guard !isFinished else {
      return
    }
    browser.stateUpdateHandler = { [weak self] state in
      self?.handle(state)
    }
    browser.resultsUpdateHandler = { [weak self] results in
      self?.replaceResults(with: results)
    }
    browser.start(queue: queue)
  }

  private func handle(_ state: BonjourBrowserState) {
    switch state {
    case .waiting(let error) where Self.isPermissionDenied(error):
      finish(throwing: HomeAssistantDiscoveryError.permissionDenied)
    case .failed(let error) where Self.isPermissionDenied(error):
      finish(throwing: HomeAssistantDiscoveryError.permissionDenied)
    case .failed(let error):
      finish(throwing: HomeAssistantDiscoveryError.browserFailed(error.debugDescription))
    case .cancelled:
      finish()
    case .setup, .ready, .waiting:
      break
    }
  }

  private func replaceResults(with results: [BonjourBrowseResult]) {
    guard !isFinished else {
      return
    }

    let resultIDs = Set(results.map(\.id))
    for id in advertisements.keys where !resultIDs.contains(id) {
      advertisements.removeValue(forKey: id)
      resolvers.removeValue(forKey: id)?.cancel()
    }
    for result in results {
      addOrUpdate(result)
    }
    publish()
  }

  private func addOrUpdate(_ result: BonjourBrowseResult) {
    let previousResolvedURL = advertisements[result.id]?.resolvedInternalURL
    advertisements[result.id] = HomeAssistantDiscoveryAdvertisement(
      id: result.id,
      serviceName: result.serviceName,
      txt: result.txt,
      resolvedInternalURL: previousResolvedURL
    )

    if HomeAssistantDiscoveryRecord.hasUsableInternalURL(in: result.txt) {
      resolvers.removeValue(forKey: result.id)?.cancel()
    } else if resolvers[result.id] == nil {
      resolve(result.endpoint, id: result.id)
    }
  }

  private func resolve(_ endpoint: NWEndpoint, id: String) {
    let resolver = makeResolver(endpoint)
    resolvers[id] = resolver
    resolver.stateUpdateHandler = { [weak self, weak resolver] state in
      guard let self, let resolver, self.resolvers[id] === resolver else {
        return
      }
      switch state {
      case .ready:
        self.resolutionCompleted(id: id, resolver: resolver)
      case .failed, .cancelled:
        self.resolvers.removeValue(forKey: id)
      case .setup, .waiting, .preparing:
        break
      }
    }
    resolver.start(queue: queue)
  }

  private func resolutionCompleted(id: String, resolver: any BonjourResolving) {
    guard resolvers[id] === resolver else {
      return
    }
    defer {
      resolvers.removeValue(forKey: id)?.cancel()
    }
    guard
      case .hostPort(let host, let port) = resolver.remoteEndpoint,
      var advertisement = advertisements[id],
      let url = Self.httpURL(host: host, port: port)
    else {
      return
    }

    advertisement = HomeAssistantDiscoveryAdvertisement(
      id: advertisement.id,
      serviceName: advertisement.serviceName,
      txt: advertisement.txt,
      resolvedInternalURL: url
    )
    advertisements[id] = advertisement
    publish()
  }

  private func publish() {
    continuation.yield(advertisements.values.sorted { $0.id < $1.id })
  }

  private func finish(throwing error: (any Error)? = nil) {
    guard !isFinished else {
      return
    }
    isFinished = true
    browser.stateUpdateHandler = nil
    browser.resultsUpdateHandler = nil
    browser.cancel()
    for resolver in resolvers.values {
      resolver.stateUpdateHandler = nil
      resolver.cancel()
    }
    resolvers.removeAll()
    advertisements.removeAll()
    if let error {
      continuation.finish(throwing: error)
    } else {
      continuation.finish()
    }
  }

  private static func isPermissionDenied(_ error: NWError) -> Bool {
    guard case .dns(let code) = error else {
      return false
    }
    return code == DNSServiceErrorType(kDNSServiceErr_PolicyDenied)
  }

  private static func httpURL(host: NWEndpoint.Host, port: NWEndpoint.Port) -> URL? {
    let hostname: String
    switch host {
    case .name(let name, _):
      hostname = name
    case .ipv4(let address):
      hostname = address.debugDescription
    case .ipv6(let address):
      hostname = address.debugDescription
    @unknown default:
      return nil
    }

    var components = URLComponents()
    components.scheme = "http"
    components.host = hostname
    components.port = Int(port.rawValue)
    return components.url
  }
}
