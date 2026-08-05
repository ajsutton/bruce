import Foundation

@MainActor
final class HomeAssistantObservationActivity {
  private(set) var isSuspended = false

  private let suspend: @MainActor @Sendable () async -> Void
  private let resume: @MainActor @Sendable () -> Void
  private var activeRegistrations: Set<UUID> = []

  init(
    suspend: @escaping @MainActor @Sendable () async -> Void,
    resume: @escaping @MainActor @Sendable () -> Void
  ) {
    self.suspend = suspend
    self.resume = resume
  }

  func observeUpdates(
    while isActive: Bool,
    registrationDidBegin: @MainActor @Sendable () -> Void = {}
  ) async {
    guard !Task.isCancelled else { return }
    let id = UUID()
    if isActive {
      activeRegistrations.insert(id)
    }
    await reconcile()
    guard !Task.isCancelled else {
      activeRegistrations.remove(id)
      await reconcile()
      return
    }
    registrationDidBegin()
    let cancellation = AsyncStream<Void> { _ in }
    for await _ in cancellation {}
    activeRegistrations.remove(id)
    await reconcile()
  }

  private func reconcile() async {
    let shouldSuspend = activeRegistrations.isEmpty
    guard shouldSuspend != isSuspended else { return }
    isSuspended = shouldSuspend
    if shouldSuspend {
      await suspend()
    } else {
      resume()
    }
  }
}
