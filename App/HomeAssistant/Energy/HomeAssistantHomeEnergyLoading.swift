protocol HomeAssistantHomeEnergyLoading: Sendable {
  var providesContinuousEnergyUpdates: Bool { get }

  func homeEnergyUpdates() -> AsyncThrowingStream<
    HomeAssistantLiveUpdate<HomeAssistantHomeEnergySnapshot>, any Error
  >
  func loadHomeEnergySnapshot() async throws -> HomeAssistantHomeEnergySnapshot
}

extension HomeAssistantHomeEnergyLoading {
  var providesContinuousEnergyUpdates: Bool { false }

  func homeEnergyUpdates() -> AsyncThrowingStream<
    HomeAssistantLiveUpdate<HomeAssistantHomeEnergySnapshot>, any Error
  > {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          continuation.yield(.live(try await loadHomeEnergySnapshot()))
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
}
