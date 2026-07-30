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
          var cachedDoors: [HomeAssistantGarageDoorSnapshot] = []
          var lastUpdate: HomeAssistantLiveUpdate<[HomeAssistantGarageDoorSnapshot]>?
          let stateUpdates = await states.stateUpdates()
          defer { stateUpdates.cancel() }
          for try await stateUpdate in stateUpdates {
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
            guard
              let doors = Self.doors(
                from: stateUpdate,
                registry: registry,
                registryGeneration: registryGeneration,
                cachedDoors: cachedDoors
              )
            else { continue }
            cachedDoors = doors
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

  private static func doors(
    from update: HomeAssistantStateUpdate,
    registry: HomeAssistantGarageDoorRegistry?,
    registryGeneration: UUID?,
    cachedDoors: [HomeAssistantGarageDoorSnapshot]
  ) -> [HomeAssistantGarageDoorSnapshot]? {
    if update.phase != .live, registryGeneration != update.generation {
      return cachedDoors
    }
    guard let registry else { return nil }
    return HomeAssistantGarageDoorSnapshot.snapshots(
      states: update.states,
      registry: registry
    )
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
