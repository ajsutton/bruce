import Combine
import Foundation

@MainActor
final class HomeEnergyBatteryHistoryStore: ObservableObject {
  @Published private(set) var batteryHistory: HomeEnergyBatteryHistory
  @Published private(set) var hasUsableHistory: Bool
  @Published private(set) var isLoading = false
  @Published private(set) var isUnavailable = false
  @Published private(set) var isStale = false
  @Published private(set) var showsProgress = false
  @Published private(set) var problem: HomeEnergyHistoryLoadProblem?

  var authenticationFailureHandler: @MainActor @Sendable () -> Void = {}

  private let loader: any HomeAssistantHomeEnergyLoading
  private let progressDelay: Duration
  private let progressSleep: @Sendable (Duration) async -> Void
  private var loadTask: Task<Void, Never>?
  private var progressTask: Task<Void, Never>?
  private var loadID = UUID()
  private var pendingHistory = HomeEnergyBatteryHistory.empty

  init(
    loader: any HomeAssistantHomeEnergyLoading,
    batteryHistory: HomeEnergyBatteryHistory = .empty,
    progressDelay: Duration = .milliseconds(500),
    progressSleep: @escaping @Sendable (Duration) async -> Void = {
      try? await Task.sleep(for: $0)
    }
  ) {
    self.loader = loader
    self.batteryHistory = batteryHistory
    hasUsableHistory = batteryHistory.hasReadings
    self.progressDelay = progressDelay
    self.progressSleep = progressSleep
  }

  deinit {
    loadTask?.cancel()
    progressTask?.cancel()
  }

  func reload() {
    loadTask?.cancel()
    pendingHistory = .empty
    let requestID = UUID()
    loadID = requestID
    isLoading = true
    isUnavailable = false
    problem = nil
    scheduleProgress(for: requestID)

    let loader = loader
    loadTask = Task { [weak self, loader] in
      guard !Task.isCancelled else { return }
      do {
        let history = try await loader.loadHomeEnergyBatteryHistory()
        try Task.checkCancellation()
        self?.publish(history, for: requestID)
      } catch {
        self?.publish(error, for: requestID)
      }
    }
  }

  func record(snapshot: HomeAssistantHomeEnergySnapshot, at timestamp: Date) {
    if isLoading {
      pendingHistory = pendingHistory.recording(snapshot: snapshot, at: timestamp)
    }
    if hasUsableHistory {
      batteryHistory = batteryHistory.recording(snapshot: snapshot, at: timestamp)
    }
  }

  @discardableResult
  func reset() -> Task<Void, Never>? {
    let cancelledTask = cancelLoad()
    batteryHistory = .empty
    hasUsableHistory = false
    isUnavailable = true
    isStale = false
    problem = nil
    return cancelledTask
  }

  @discardableResult
  func invalidate() -> Task<Void, Never>? {
    let cancelledTask = cancelLoad()
    isUnavailable = !hasUsableHistory
    isStale = hasUsableHistory
    problem = nil
    return cancelledTask
  }

  private func publish(_ history: HomeEnergyBatteryHistory, for requestID: UUID) {
    guard loadID == requestID, !Task.isCancelled else { return }
    if history.hasReadings {
      batteryHistory = history.mergingLiveReadings(from: pendingHistory)
      hasUsableHistory = true
      isStale = false
    } else if hasUsableHistory {
      isStale = true
    }
    problem = nil
    isUnavailable = !hasUsableHistory
    finishLoad()
  }

  private func publish(_ error: any Error, for requestID: UUID) {
    guard loadID == requestID else { return }
    guard !Task.isCancelled, !HomeAssistantHomeEnergyStore.isCancellation(error) else {
      isUnavailable = !hasUsableHistory
      isStale = hasUsableHistory
      finishLoad()
      return
    }
    if HomeAssistantHomeEnergyStore.problem(for: error) == .signInRequired {
      authenticationFailureHandler()
      guard loadID == requestID else { return }
    }
    problem = .loadFailed
    isUnavailable = !hasUsableHistory
    isStale = hasUsableHistory
    finishLoad()
  }

  private func scheduleProgress(for requestID: UUID) {
    progressTask?.cancel()
    showsProgress = false
    guard !hasUsableHistory else { return }
    progressTask = Task { [weak self, progressDelay, progressSleep] in
      await progressSleep(progressDelay)
      guard !Task.isCancelled else { return }
      guard
        let self,
        self.loadID == requestID,
        self.isLoading,
        !self.hasUsableHistory
      else {
        return
      }
      self.showsProgress = true
    }
  }

  private func finishLoad() {
    progressTask?.cancel()
    progressTask = nil
    isLoading = false
    showsProgress = false
    pendingHistory = .empty
  }

  private func cancelLoad() -> Task<Void, Never>? {
    let cancelledTask = loadTask
    loadTask?.cancel()
    loadTask = nil
    loadID = UUID()
    finishLoad()
    return cancelledTask
  }
}
