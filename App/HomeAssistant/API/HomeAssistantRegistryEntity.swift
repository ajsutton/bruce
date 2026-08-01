import Foundation

struct HomeAssistantRegistryEntity: Decodable, Equatable, Sendable {
  let id: String
  let platform: String?
  let uniqueID: String?
  let deviceID: String?
  let areaID: String?
  let icon: String?
  let originalIcon: String?
  let labelIDs: [String]

  init(
    id: String,
    platform: String? = nil,
    uniqueID: String? = nil,
    deviceID: String?,
    areaID: String?,
    icon: String?,
    originalIcon: String?,
    labelIDs: [String] = []
  ) {
    self.id = id
    self.platform = platform
    self.uniqueID = uniqueID
    self.deviceID = deviceID
    self.areaID = areaID
    self.icon = icon
    self.originalIcon = originalIcon
    self.labelIDs = labelIDs
  }

  enum CodingKeys: String, CodingKey {
    case id = "entity_id"
    case platform
    case uniqueID = "unique_id"
    case deviceID = "device_id"
    case areaID = "area_id"
    case icon
    case originalIcon = "original_icon"
    case labelIDs = "labels"
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    platform = try container.decodeIfPresent(String.self, forKey: .platform)
    uniqueID = try container.decodeIfPresent(String.self, forKey: .uniqueID)
    deviceID = try container.decodeIfPresent(String.self, forKey: .deviceID)
    areaID = try container.decodeIfPresent(String.self, forKey: .areaID)
    icon = try container.decodeIfPresent(String.self, forKey: .icon)
    originalIcon = try container.decodeIfPresent(String.self, forKey: .originalIcon)
    labelIDs = try container.decodeIfPresent([String].self, forKey: .labelIDs) ?? []
  }
}

struct HomeAssistantRegistryDevice: Decodable, Equatable, Sendable {
  let id: String
  let areaID: String?
  let name: String?
  let nameByUser: String?
  let labelIDs: [String]

  init(
    id: String,
    areaID: String?,
    name: String? = nil,
    nameByUser: String? = nil,
    labelIDs: [String] = []
  ) {
    self.id = id
    self.areaID = areaID
    self.name = name
    self.nameByUser = nameByUser
    self.labelIDs = labelIDs
  }

  enum CodingKeys: String, CodingKey {
    case id
    case areaID = "area_id"
    case name
    case nameByUser = "name_by_user"
    case labelIDs = "labels"
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    areaID = try container.decodeIfPresent(String.self, forKey: .areaID)
    name = try container.decodeIfPresent(String.self, forKey: .name)
    nameByUser = try container.decodeIfPresent(String.self, forKey: .nameByUser)
    labelIDs = try container.decodeIfPresent([String].self, forKey: .labelIDs) ?? []
  }
}

struct HomeAssistantGarageDoorRegistry: Equatable, Sendable {
  let deviceIDByEntityID: [String: String]
  let deviceNameByID: [String: String]
}

struct HomeAssistantRegistryArea: Decodable, Equatable, Sendable {
  let id: String
  let name: String
  let floorID: String?
  let icon: String?
  let labelIDs: [String]

  init(
    id: String,
    name: String? = nil,
    floorID: String? = nil,
    icon: String?,
    labelIDs: [String] = []
  ) {
    self.id = id
    self.name = name ?? id
    self.floorID = floorID
    self.icon = icon
    self.labelIDs = labelIDs
  }

  enum CodingKeys: String, CodingKey {
    case id = "area_id"
    case name
    case floorID = "floor_id"
    case icon
    case labelIDs = "labels"
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    name = try container.decodeIfPresent(String.self, forKey: .name) ?? id
    floorID = try container.decodeIfPresent(String.self, forKey: .floorID)
    icon = try container.decodeIfPresent(String.self, forKey: .icon)
    labelIDs = try container.decodeIfPresent([String].self, forKey: .labelIDs) ?? []
  }
}

struct HomeAssistantRegistryLabel: Decodable, Equatable, Sendable {
  let id: String
  let name: String

  enum CodingKeys: String, CodingKey {
    case id = "label_id"
    case name
  }
}

struct HomeAssistantRegistryFloor: Decodable, Equatable, Sendable {
  let id: String
  let name: String
  let level: Int?

  enum CodingKeys: String, CodingKey {
    case id = "floor_id"
    case name, level
  }
}
