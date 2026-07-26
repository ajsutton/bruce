import Combine
import Foundation

struct HomeAssistantConnectionCandidate: Equatable, Sendable {
  enum Source: Equatable, Sendable {
    case discovered
    case manual
  }

  let instanceID: String?
  let name: String
  let internalURL: URL?
  let externalURL: URL?
  let activeURL: URL
  let source: Source
}

@MainActor
final class HomeAssistantSetupStore: ObservableObject {
  enum Step: Equatable {
    case restoring
    case restoreFailed
    case introduction
    case chooseServer
    case manualEntry
    case confirmation(HomeAssistantConnectionCandidate)
    case unencryptedWarning(HomeAssistantConnectionCandidate)
    case onboardingRequired(HomeAssistantInstance)
    case readyForAuthentication(HomeAssistantConnectionCandidate)
    case authenticationFailed(
      HomeAssistantConnectionCandidate,
      HomeAssistantAuthenticationFailure
    )
    case configured(HomeAssistantCredentials)
    case connected(HomeAssistantCredentials)
    case cancelled
  }

  enum AuthenticationProblem: Equatable {
    case rejected
    case inactiveUser
    case unavailable
    case invalidCallback
    case verificationFailed
    case couldNotSave
    case other
  }

  enum DiscoveryProblem: Equatable {
    case permissionDenied
    case failed
  }

  enum ConnectionCheckProblem: Equatable {
    case networkUnavailable
    case serverRejectedRequest
    case incompatibleServer
    case invalidResponse
    case other
  }

  enum ConnectionCheckState: Equatable {
    case idle
    case checking
    case succeeded
    case failed(ConnectionCheckProblem)
    case reauthenticationRequired
    case disconnectFailed
  }

  @Published private(set) var step: Step = .introduction
  @Published private(set) var instances: [HomeAssistantInstance] = []
  @Published private(set) var selectedInstanceID: String?
  @Published private(set) var isSearching = false
  @Published private(set) var discoveryProblem: DiscoveryProblem?
  @Published private(set) var manualValidationError: HomeAssistantServerAddress.ValidationError?
  @Published var manualAddress = ""

  private let discovery: any HomeAssistantDiscovering
  private let connectionController: HomeAssistantConnectionController
  private let webAuthenticationPresenter: HomeAssistantWebAuthenticationPresenter?
  private var discoveryTask: Task<Void, Never>?
  private var discoveryGeneration = UUID()
  private var selectionWasAutomatic = false
  private var connectionObservation: AnyCancellable?

  init(
    discovery: any HomeAssistantDiscovering,
    connection: (any HomeAssistantConnecting)? = nil,
    webAuthenticationPresenter: HomeAssistantWebAuthenticationPresenter? = nil
  ) {
    self.discovery = discovery
    self.webAuthenticationPresenter = webAuthenticationPresenter
    connectionController = HomeAssistantConnectionController(connection: connection)
    connectionController.onStepChange = { [weak self] step in
      self?.step = step
    }
    connectionObservation = connectionController.objectWillChange.sink { [weak self] _ in
      self?.objectWillChange.send()
    }
  }

  deinit {
    discoveryTask?.cancel()
  }

  var connectedCredentials: HomeAssistantCredentials? {
    connectionController.connectedCredentials
  }

  var connectionCheckState: ConnectionCheckState {
    connectionController.connectionCheckState
  }

  var isDisconnecting: Bool {
    connectionController.isDisconnecting
  }

  var canConfirmSelectedInstance: Bool {
    guard
      let selectedInstanceID,
      let instance = instances.first(where: { $0.id == selectedInstanceID })
    else {
      return false
    }
    return HomeAssistantServerSelection.candidate(from: instance) != nil
  }

  func startDiscovery() {
    stopDiscovery()
    connectionController.step = .chooseServer
    isSearching = true
    discoveryProblem = nil
    let generation = UUID()
    discoveryGeneration = generation
    discoveryTask = Task { [weak self, discovery] in
      do {
        for try await snapshot in discovery.snapshots() {
          try Task.checkCancellation()
          guard let self, self.discoveryGeneration == generation else {
            return
          }
          self.receive(snapshot.instances)
        }
        guard let self, self.discoveryGeneration == generation else {
          return
        }
        self.isSearching = false
        self.discoveryTask = nil
      } catch is CancellationError {
      } catch {
        guard let self, self.discoveryGeneration == generation else {
          return
        }
        self.isSearching = false
        self.discoveryTask = nil
        self.discoveryProblem =
          error as? HomeAssistantDiscoveryError == .permissionDenied ? .permissionDenied : .failed
      }
    }
  }

  func stopDiscovery() {
    discoveryGeneration = UUID()
    discoveryTask?.cancel()
    discoveryTask = nil
    isSearching = false
  }

  func selectInstance(id: String) {
    guard instances.contains(where: { $0.id == id }) else {
      return
    }
    selectedInstanceID = id
    selectionWasAutomatic = false
  }

  func confirmSelectedInstance() {
    guard
      let selectedInstanceID,
      let instance = instances.first(where: { $0.id == selectedInstanceID })
    else {
      return
    }
    if instance.isOnboarding {
      connectionController.step = .onboardingRequired(instance)
      return
    }
    guard let candidate = HomeAssistantServerSelection.candidate(from: instance) else {
      return
    }
    connectionController.step =
      candidate.activeURL.scheme?.lowercased() == "http"
      ? .unencryptedWarning(candidate)
      : .confirmation(candidate)
  }

  func showManualEntry() {
    manualValidationError = nil
    connectionController.step = .manualEntry
  }

  func updateManualAddress(_ value: String) {
    manualAddress = value
    manualValidationError = nil
  }

  func validateManualAddress() {
    do {
      let address = try HomeAssistantServerAddress(manualAddress)
      let candidate = HomeAssistantConnectionCandidate(
        instanceID: nil,
        name: address.url.host() ?? "Home Assistant",
        internalURL: address.url,
        externalURL: nil,
        activeURL: address.url,
        source: .manual
      )
      connectionController.step =
        address.usesUnencryptedHTTP ? .unencryptedWarning(candidate) : .confirmation(candidate)
    } catch {
      manualValidationError = error
    }
  }

  func acceptUnencryptedConnection() {
    guard case .unencryptedWarning(let candidate) = step else {
      return
    }
    connectionController.step = .confirmation(candidate)
  }

  func rejectUnencryptedConnection() {
    guard case .unencryptedWarning(let candidate) = step else {
      return
    }
    switch candidate.source {
    case .discovered:
      connectionController.step = .chooseServer
    case .manual:
      connectionController.step = .manualEntry
    }
  }

  private func receive(_ newInstances: [HomeAssistantInstance]) {
    let selection = HomeAssistantServerSelection.updatedState(
      instances: newInstances,
      previousCount: instances.count,
      selectedInstanceID: selectedInstanceID,
      selectionWasAutomatic: selectionWasAutomatic
    )
    instances = newInstances
    selectedInstanceID = selection.instanceID
    selectionWasAutomatic = selection.wasAutomatic
  }

  func requestAuthentication() {
    stopDiscovery()
    connectionController.requestAuthentication()
  }

  func showDiscoveredHomes() {
    connectionController.step = .chooseServer
    if !isSearching {
      startDiscovery()
    }
  }

  func cancelAuthentication() {
    connectionController.cancelAuthentication()
  }

  func retryAuthentication() {
    connectionController.retryAuthentication()
  }

  func restoreSavedConnection() async {
    await connectionController.restoreSavedConnection()
  }

  func testConnection() {
    connectionController.testConnection()
  }

  func reauthenticate() {
    connectionController.reauthenticate()
  }

  func changeServer() {
    connectionController.changeServer()
  }

  func disconnect() {
    connectionController.disconnect()
  }

  func cancel() {
    stopDiscovery()
    connectionController.cancel()
  }
}

extension HomeAssistantSetupStore.ConnectionCheckState {
  var canSignInAgain: Bool {
    switch self {
    case .failed, .reauthenticationRequired:
      true
    case .idle, .checking, .succeeded, .disconnectFailed:
      false
    }
  }
}

extension HomeAssistantSetupStore {
  func registerWebAuthenticationAction(
    ownerID: UUID,
    _ authenticationAction: @escaping HomeAssistantWebAuthenticationPresenter.AuthenticationAction
  ) {
    webAuthenticationPresenter?.register(
      ownerID: ownerID,
      authenticationAction: authenticationAction
    )
  }

  func unregisterWebAuthenticationAction(ownerID: UUID) {
    webAuthenticationPresenter?.unregister(ownerID: ownerID)
  }
}
