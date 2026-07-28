import Foundation

@MainActor
final class HomeAssistantEVChargingTasks {
  struct ModeChangeHandlers {
    let isActive: @MainActor () -> Bool
    let receive: @MainActor (Result<HomeAssistantEVChargingMode, any Error>) -> Void
    let onTimeout: @MainActor @Sendable () -> Void
    let onCancel: @MainActor @Sendable () -> Void
  }

  private var modeChange: Task<Void, Never>?
  private var updateTimeout: Task<Void, Never>?
  private var reconciliation: Task<Void, Never>?
  private var progress: Task<Void, Never>?
  private var waiter: CheckedContinuation<Void, Never>?

  deinit {
    modeChange?.cancel()
    updateTimeout?.cancel()
    reconciliation?.cancel()
    progress?.cancel()
    waiter?.resume()
  }

  func requestModeChange(
    client: any HomeAssistantEVCharging,
    requestedMode: HomeAssistantEVChargingMode,
    receive: @escaping @MainActor (Result<HomeAssistantEVChargingMode, any Error>) -> Void
  ) {
    modeChange?.cancel()
    modeChange = Task {
      let result: Result<HomeAssistantEVChargingMode, any Error>
      do {
        result = .success(try await client.setEVChargingMode(requestedMode))
      } catch {
        result = .failure(error)
      }
      receive(result)
    }
  }

  func changeMode(
    client: any HomeAssistantEVCharging,
    requestedMode: HomeAssistantEVChargingMode,
    timeout: Duration,
    sleep: @escaping @Sendable (Duration) async -> Void,
    handlers: ModeChangeHandlers
  ) async {
    requestModeChange(
      client: client,
      requestedMode: requestedMode,
      receive: handlers.receive
    )
    scheduleTimeout(duration: timeout, sleep: sleep, action: handlers.onTimeout)
    await waitForModeChange(while: handlers.isActive, onCancel: handlers.onCancel)
  }

  private func waitForModeChange(
    while isActive: @escaping @MainActor () -> Bool,
    onCancel: @escaping @MainActor @Sendable () -> Void
  ) async {
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        guard isActive() else {
          continuation.resume()
          return
        }
        waiter = continuation
      }
    } onCancel: {
      Task { @MainActor in onCancel() }
    }
  }

  func finishModeChange() {
    modeChange = nil
    let waiter = waiter
    self.waiter = nil
    waiter?.resume()
  }

  func cancelModeChange() {
    modeChange?.cancel()
    modeChange = nil
  }

  private func scheduleTimeout(
    duration: Duration,
    sleep: @escaping @Sendable (Duration) async -> Void,
    action: @escaping @MainActor @Sendable () -> Void
  ) {
    finishTimeout()
    updateTimeout = Task {
      await sleep(duration)
      guard !Task.isCancelled else { return }
      action()
    }
  }

  func finishTimeout() {
    updateTimeout?.cancel()
    updateTimeout = nil
  }

  func loadReconciliation(
    client: any HomeAssistantEVCharging,
    receive:
      @escaping @MainActor (
        Result<HomeAssistantEVChargingSnapshot, any Error>
      ) -> Void
  ) {
    reconciliation?.cancel()
    reconciliation = Task {
      let result: Result<HomeAssistantEVChargingSnapshot, any Error>
      do {
        result = .success(try await client.loadEVChargingSnapshot())
      } catch {
        result = .failure(error)
      }
      guard !Task.isCancelled else { return }
      receive(result)
    }
  }

  func finishReconciliation() {
    reconciliation?.cancel()
    reconciliation = nil
  }

  func scheduleProgress(
    delay: Duration,
    sleep: @escaping @Sendable (Duration) async -> Void,
    show: @escaping @MainActor @Sendable () -> Void
  ) {
    finishProgress()
    progress = Task {
      await sleep(delay)
      guard !Task.isCancelled else { return }
      show()
    }
  }

  func finishProgress() {
    progress?.cancel()
    progress = nil
  }
}
