import Foundation

extension HomeAssistantAPIClient {
  func loadHomeEnergyBatteryHistory() async throws -> HomeEnergyBatteryHistory {
    let response = try await loadHomeEnergyHistory(
      entityIDs: [HomeAssistantHomeEnergySnapshot.batteryStateOfChargeEntityID]
    )
    return try HomeEnergyBatteryHistory(
      data: response.data,
      interval: response.interval
    )
  }

  func loadHomeEnergyPriceHistory() async throws -> HomeEnergyPriceHistory {
    let response = try await loadHomeEnergyHistory(
      entityIDs: [
        HomeAssistantHomeEnergySnapshot.generalPriceEntityID,
        HomeAssistantHomeEnergySnapshot.feedInPriceEntityID,
      ]
    )
    return try HomeEnergyPriceHistory(
      data: response.data,
      interval: response.interval
    )
  }

  private func loadHomeEnergyHistory(
    entityIDs: [String]
  ) async throws -> (data: Data, interval: DateInterval) {
    let end = now()
    let start = end.addingTimeInterval(-24 * 60 * 60)
    let timestampStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: false)
    let data = try await session.authenticatedGET(
      path: "api/history/period/\(start.formatted(timestampStyle))",
      queryItems: [
        URLQueryItem(name: "end_time", value: end.formatted(timestampStyle)),
        URLQueryItem(
          name: "filter_entity_id",
          value: entityIDs.joined(separator: ",")
        ),
        URLQueryItem(name: "minimal_response", value: nil),
        URLQueryItem(name: "no_attributes", value: nil),
      ]
    )
    return (data, DateInterval(start: start, end: end))
  }
}
