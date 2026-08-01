import Foundation
import XCTest

@testable import Bruce

final class HomeAssistantRegistryClientTests: XCTestCase {
  func testRegistryResolvesClimateMetadataAndPresetLabels() {
    let metadata = HomeAssistantRegistryClient.climateMetadata(
      entities: climateMetadataEntities,
      devices: climateMetadataDevices,
      areas: climateMetadataAreas,
      floors: climateMetadataFloors,
      labels: climateMetadataLabels
    )

    XCTAssertEqual(Set(metadata.keys), ["climate.dining", "climate.retreat"])
    XCTAssertEqual(metadata["climate.dining"]?.icon, "mdi:table-furniture")
    XCTAssertEqual(metadata["climate.dining"]?.floor?.name, "Downstairs")
    XCTAssertEqual(
      metadata["climate.dining"]?.presetLabels.map(\.name),
      ["Downstairs zones", "Living spaces", "Shared"]
    )
    XCTAssertEqual(metadata["climate.retreat"]?.icon, "mdi:air-conditioner")
    XCTAssertEqual(metadata["climate.retreat"]?.floor?.name, "Upstairs")
    XCTAssertEqual(metadata["climate.retreat"]?.presetLabels, [])
  }

  func testRegistryUsesOriginalIconOnlyWhenNoExplicitOrAreaIconExists() {
    let metadata = HomeAssistantRegistryClient.climateMetadata(
      entities: [
        HomeAssistantRegistryEntity(
          id: "climate.lounge",
          deviceID: nil,
          areaID: nil,
          icon: nil,
          originalIcon: "mdi:thermostat"
        )
      ],
      devices: [],
      areas: []
    )

    XCTAssertEqual(
      metadata,
      [
        "climate.lounge": HomeAssistantClimateMetadata(
          icon: "mdi:thermostat",
          kind: .other
        )
      ]
    )
  }

  func testRegistryNormalizesAirTouchEntityKinds() {
    let metadata = HomeAssistantRegistryClient.climateMetadata(
      entities: [
        HomeAssistantRegistryEntity(
          id: "climate.ac_0",
          platform: "airtouch5",
          uniqueID: "ac_0",
          deviceID: nil,
          areaID: nil,
          icon: nil,
          originalIcon: nil
        ),
        HomeAssistantRegistryEntity(
          id: "climate.dining",
          platform: "airtouch5",
          uniqueID: "zone_0",
          deviceID: nil,
          areaID: nil,
          icon: nil,
          originalIcon: nil
        ),
        HomeAssistantRegistryEntity(
          id: "climate.other",
          platform: "another_platform",
          uniqueID: "ac_0",
          deviceID: nil,
          areaID: nil,
          icon: nil,
          originalIcon: nil
        ),
      ],
      devices: [],
      areas: []
    )

    XCTAssertEqual(metadata["climate.ac_0"]?.kind, .airConditioner)
    XCTAssertEqual(metadata["climate.dining"]?.kind, .zone)
    XCTAssertEqual(metadata["climate.other"]?.kind, .other)
  }

  func testRegistryAssociatesGarageCompanionsByDeviceIdentity() {
    let registry = HomeAssistantRegistryClient.garageDoorRegistry(
      entities: [
        HomeAssistantRegistryEntity(
          id: "cover.side_entry",
          deviceID: "garage-device",
          areaID: nil,
          icon: nil,
          originalIcon: nil
        ),
        HomeAssistantRegistryEntity(
          id: "light.side_entry_opener",
          deviceID: "garage-device",
          areaID: nil,
          icon: nil,
          originalIcon: nil
        ),
      ],
      devices: [
        HomeAssistantRegistryDevice(
          id: "garage-device",
          areaID: nil,
          name: "Opener 123",
          nameByUser: "Side Garage"
        )
      ]
    )

    XCTAssertEqual(registry.deviceIDByEntityID["cover.side_entry"], "garage-device")
    XCTAssertEqual(
      registry.deviceIDByEntityID["light.side_entry_opener"],
      "garage-device"
    )
    XCTAssertEqual(registry.deviceNameByID["garage-device"], "Side Garage")
  }

  func testWebSocketLoadsRegistriesAfterAuthenticating() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(apiResponses: [])
    try await session.install(fixture.credentials())
    let connection = StubHomeAssistantWebSocketConnection(
      receivedMessages: climateRegistryMessages
    )
    let client = HomeAssistantRegistryClient(
      session: session,
      connector: StubHomeAssistantWebSocketConnector(connection: connection)
    )

    let metadata = try await client.loadClimateMetadata()

    XCTAssertEqual(metadata["climate.dining"]?.kind, .zone)
    XCTAssertEqual(metadata["climate.dining"]?.floor?.name, "Downstairs")
    XCTAssertEqual(metadata["climate.dining"]?.presetLabels.map(\.name), ["Bedrooms"])
    XCTAssertEqual(connection.connectedURL?.absoluteString, "ws://home.local:8123/api/websocket")
    XCTAssertEqual(
      connection.sentMessageTypes,
      [
        "auth",
        "config/entity_registry/list",
        "config/device_registry/list",
        "config/area_registry/list",
        "config/floor_registry/list",
        "config/label_registry/list",
      ]
    )
    XCTAssertTrue(connection.isCancelled)
  }

  func testRejectedWebSocketAuthenticationFailsAndClosesConnection() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(apiResponses: [])
    try await session.install(fixture.credentials())
    let connection = StubHomeAssistantWebSocketConnection(
      receivedMessages: [
        #"{"type":"auth_required"}"#,
        #"{"type":"auth_invalid"}"#,
      ]
    )
    let client = HomeAssistantRegistryClient(
      session: session,
      connector: StubHomeAssistantWebSocketConnector(connection: connection)
    )

    do {
      _ = try await client.loadClimateMetadata()
      XCTFail("Expected WebSocket authentication to be rejected.")
    } catch HomeAssistantAPIError.unauthorized {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    XCTAssertTrue(connection.isCancelled)
  }

  func testCancellingRegistryLoadClosesBlockedWebSocket() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(apiResponses: [])
    try await session.install(fixture.credentials())
    let connection = BlockingHomeAssistantWebSocketConnection()
    let client = HomeAssistantRegistryClient(
      session: session,
      connector: BlockingHomeAssistantWebSocketConnector(connection: connection)
    )
    let load = Task {
      try await client.loadClimateMetadata()
    }
    await fulfillment(of: [connection.blockedReceiveStarted], timeout: 1)

    load.cancel()

    do {
      _ = try await load.value
      XCTFail("Expected the registry load to be cancelled.")
    } catch is CancellationError {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    XCTAssertTrue(connection.isCancelled)
  }
}

private let climateMetadataEntities = [
  registryEntity(
    "climate.dining",
    deviceID: "dining-device",
    areaID: nil,
    labelIDs: ["climate_preset_shared"]
  ),
  registryEntity(
    "climate.retreat",
    deviceID: "retreat-device",
    areaID: "retreat",
    icon: "mdi:air-conditioner"
  ),
  registryEntity(
    "light.dining",
    deviceID: "dining-device",
    areaID: nil,
    icon: "mdi:lightbulb"
  ),
]

private let climateMetadataDevices = [
  HomeAssistantRegistryDevice(
    id: "dining-device",
    areaID: "dining-room",
    labelIDs: ["climate_preset_downstairs"]
  ),
  HomeAssistantRegistryDevice(id: "retreat-device", areaID: "wrong-area"),
]

private let climateMetadataAreas = [
  HomeAssistantRegistryArea(
    id: "dining-room",
    name: "Dining Room",
    floorID: "downstairs",
    icon: "mdi:table-furniture",
    labelIDs: ["climate_preset_living_spaces", "unrelated"]
  ),
  HomeAssistantRegistryArea(
    id: "retreat",
    name: "Retreat",
    floorID: "upstairs",
    icon: "mdi:sofa-outline"
  ),
]

private let climateMetadataFloors = [
  HomeAssistantRegistryFloor(id: "downstairs", name: "Downstairs", level: 0),
  HomeAssistantRegistryFloor(id: "upstairs", name: "Upstairs", level: 1),
]

private let climateMetadataLabels = [
  HomeAssistantRegistryLabel(
    id: "climate_preset_downstairs",
    name: "Climate preset: Downstairs zones"
  ),
  HomeAssistantRegistryLabel(
    id: "climate_preset_living_spaces",
    name: "Climate preset: Living spaces"
  ),
  HomeAssistantRegistryLabel(
    id: "climate_preset_shared",
    name: "Climate preset: Shared"
  ),
  HomeAssistantRegistryLabel(id: "unrelated", name: "Heavy energy usage"),
]

private func registryEntity(
  _ id: String,
  deviceID: String?,
  areaID: String?,
  icon: String? = nil,
  labelIDs: [String] = []
) -> HomeAssistantRegistryEntity {
  HomeAssistantRegistryEntity(
    id: id,
    deviceID: deviceID,
    areaID: areaID,
    icon: icon,
    originalIcon: nil,
    labelIDs: labelIDs
  )
}

private let climateRegistryMessages = [
  #"{"type":"auth_required"}"#,
  #"{"type":"auth_ok"}"#,
  """
  {"id":1,"type":"result","success":true,"result":[
    {"entity_id":"climate.dining","platform":"airtouch5","unique_id":"zone_0",
     "device_id":"dining-device","area_id":null,"icon":null,"original_icon":null}
  ]}
  """,
  """
  {"id":2,"type":"result","success":true,"result":[
    {"id":"dining-device","area_id":"dining-room"}
  ]}
  """,
  """
  {"id":3,"type":"result","success":true,"result":[
    {"area_id":"dining-room","name":"Dining Room","floor_id":"downstairs",
     "icon":"mdi:table-furniture","labels":["climate_preset_bedrooms"]}
  ]}
  """,
  """
  {"id":4,"type":"result","success":true,"result":[
    {"floor_id":"downstairs","name":"Downstairs","level":0}
  ]}
  """,
  """
  {"id":5,"type":"result","success":true,"result":[
    {"label_id":"climate_preset_bedrooms","name":"Climate preset: Bedrooms"}
  ]}
  """,
]
