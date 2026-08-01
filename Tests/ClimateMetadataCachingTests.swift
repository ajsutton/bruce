import XCTest

@testable import Bruce

final class ClimateMetadataCachingTests: XCTestCase {
  func testTemperatureLoadingKeepsCachedMetadataAfterTransientRegistryFailure() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [
        .success(configuration, statusCode: 200),
        .success(climateState, statusCode: 200),
        .success(configuration, statusCode: 200),
        .success(climateState, statusCode: 200),
      ]
    )
    try await session.install(fixture.credentials())
    let metadata = HomeAssistantClimateMetadata(icon: "mdi:bed", kind: .other)
    let metadataLoader = QueueClimateMetadataLoader(
      results: [
        .success(["climate.bedroom": metadata]),
        .failure(HomeAssistantAPIError.server(statusCode: 503)),
      ]
    )
    let client = HomeAssistantAPIClient(
      session: session,
      climateMetadataLoader: metadataLoader
    )

    _ = try await client.loadTemperatures()
    let refreshed = try await client.loadTemperatures()

    XCTAssertEqual(refreshed.first?.icon, "mdi:bed")
  }

  func testCachedMetadataDoesNotHideAuthenticationFailure() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [
        .success(configuration, statusCode: 200),
        .success(climateState, statusCode: 200),
        .success(configuration, statusCode: 200),
      ]
    )
    try await session.install(fixture.credentials())
    let metadataLoader = QueueClimateMetadataLoader(
      results: [
        .success([:]),
        .failure(HomeAssistantAPIError.unauthorized),
      ]
    )
    let client = HomeAssistantAPIClient(
      session: session,
      climateMetadataLoader: metadataLoader
    )
    _ = try await client.loadTemperatures()

    do {
      _ = try await client.loadTemperatures()
      XCTFail("Expected registry authentication failure to propagate.")
    } catch HomeAssistantAPIError.unauthorized {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }
}

private let configuration = Data(
  #"{"unit_system":{"temperature":"°C"}}"#.utf8
)

private let climateState = Data(
  #"[{"entity_id":"climate.bedroom","state":"cool","attributes":{"current_temperature":21,"friendly_name":"Bedroom"}}]"#
    .utf8
)

private final class QueueClimateMetadataLoader:
  HomeAssistantClimateMetadataLoading, @unchecked Sendable
{
  typealias Output = [String: HomeAssistantClimateMetadata]

  private let lock = NSLock()
  private var results: [Result<Output, any Error>]

  init(results: [Result<Output, any Error>]) {
    self.results = results
  }

  func loadClimateMetadata() async throws -> Output {
    let result = lock.withLock { results.removeFirst() }
    return try result.get()
  }
}
