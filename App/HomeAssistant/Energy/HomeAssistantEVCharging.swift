enum HomeAssistantEVChargingUpdate: Equatable, Sendable {
  case absent
  case live(HomeAssistantEVChargingSnapshot)
  case refreshing(HomeAssistantEVChargingSnapshot?)
  case reconnecting(HomeAssistantEVChargingSnapshot?)
  case unavailable(HomeAssistantEVChargingSnapshot?)
}

protocol HomeAssistantEVCharging: Sendable {
  var providesContinuousUpdates: Bool { get }

  func evChargingUpdates() -> AsyncThrowingStream<
    HomeAssistantEVChargingUpdate, any Error
  >
  func loadEVChargingMode() async throws -> HomeAssistantEVChargingMode
  func loadEVChargingSnapshot() async throws -> HomeAssistantEVChargingSnapshot
  func setEVChargingMode(
    _ mode: HomeAssistantEVChargingMode
  ) async throws -> HomeAssistantEVChargingMode
}

extension HomeAssistantEVCharging {
  var providesContinuousUpdates: Bool { false }

  func evChargingUpdates() -> AsyncThrowingStream<
    HomeAssistantEVChargingUpdate, any Error
  > {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          continuation.yield(.live(try await loadEVChargingSnapshot()))
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }

  func loadEVChargingSnapshot() async throws -> HomeAssistantEVChargingSnapshot {
    HomeAssistantEVChargingSnapshot(
      mode: try await loadEVChargingMode(),
      activity: .unavailable
    )
  }
}
