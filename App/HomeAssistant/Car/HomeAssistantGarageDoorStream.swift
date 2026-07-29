import Foundation

struct HomeAssistantGarageDoorStream: HomeAssistantGarageDoorLoading {
  let providesContinuousUpdates = true

  private let states: any HomeAssistantStateLoading
  private let registryLoader: any HomeAssistantGarageDoorRegistryLoading

  init(
    states: any HomeAssistantStateLoading,
    registryLoader: any HomeAssistantGarageDoorRegistryLoading
  ) {
    self.states = states
    self.registryLoader = registryLoader
  }

  func garageDoorUpdates() -> AsyncThrowingStream<
    HomeAssistantLiveUpdate<[HomeAssistantGarageDoorSnapshot]>, any Error
  > {
    AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
      let task = Task {
        do {
          var registry: HomeAssistantGarageDoorRegistry?
          var registryGeneration: UUID?
          var lastUpdate: HomeAssistantLiveUpdate<[HomeAssistantGarageDoorSnapshot]>?
          for try await stateUpdate in await states.stateUpdates() {
            try Task.checkCancellation()
            if stateUpdate.phase == .live, registryGeneration != stateUpdate.generation {
              do {
                registry = try await registryLoader.loadGarageDoorRegistry()
              } catch is CancellationError {
                throw CancellationError()
              } catch {
                registry = HomeAssistantGarageDoorRegistry(
                  deviceIDByEntityID: [:],
                  deviceNameByID: [:]
                )
              }
              registryGeneration = stateUpdate.generation
            }
            guard let registry else {
              continue
            }
            let doors = HomeAssistantGarageDoorSnapshot.snapshots(
              states: stateUpdate.states,
              registry: registry
            )
            let update = Self.update(doors: doors, phase: stateUpdate.phase)
            guard update != lastUpdate else { continue }
            lastUpdate = update
            continuation.yield(update)
          }
          continuation.finish()
        } catch is CancellationError {
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

  func loadGarageDoors() async throws -> [HomeAssistantGarageDoorSnapshot] {
    for try await update in garageDoorUpdates() {
      if case .live(let doors) = update {
        return doors
      }
    }
    throw HomeAssistantAPIError.invalidResponse
  }

  private static func update(
    doors: [HomeAssistantGarageDoorSnapshot],
    phase: HomeAssistantStateUpdate.Phase
  ) -> HomeAssistantLiveUpdate<[HomeAssistantGarageDoorSnapshot]> {
    switch phase {
    case .live: .live(doors)
    case .refreshing: .refreshing(doors)
    case .reconnecting: .reconnecting(doors)
    }
  }
}
