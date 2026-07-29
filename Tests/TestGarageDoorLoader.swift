@testable import Bruce

struct TestGarageDoorLoader: HomeAssistantGarageDoorLoading {
  let providesContinuousUpdates = true

  func loadGarageDoors() async throws -> [HomeAssistantGarageDoorSnapshot] {
    []
  }

  func garageDoorUpdates() -> AsyncThrowingStream<
    HomeAssistantLiveUpdate<[HomeAssistantGarageDoorSnapshot]>, any Error
  > {
    AsyncThrowingStream { continuation in
      continuation.yield(.live([]))
    }
  }
}
