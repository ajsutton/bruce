struct HomeAssistantTemperatureSummary {
  let airConditioners: [HomeAssistantTemperatureReading]
  let rooms: [HomeAssistantTemperatureReading]

  init(readings: [HomeAssistantTemperatureReading]) {
    airConditioners = readings.filter { $0.kind == .airConditioner }
    rooms = readings.filter { $0.kind != .airConditioner }
  }

  var averageRoomTemperature: Double? {
    let availableValues = rooms.compactMap { reading in
      reading.powerState == .unavailable ? nil : reading.value
    }
    guard !availableValues.isEmpty else {
      return nil
    }
    return availableValues.reduce(0, +) / Double(availableValues.count)
  }
}
