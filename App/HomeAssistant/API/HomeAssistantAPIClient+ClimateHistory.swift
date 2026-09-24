import Foundation

protocol ClimateHistoryLoading: Sendable {
  func loadClimateHistory(interval: DateInterval) async throws -> ClimateHistory
}

extension HomeAssistantAPIClient: ClimateHistoryLoading {
  func loadClimateHistory(interval: DateInterval) async throws -> ClimateHistory {
    let style = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    let data = try await session.authenticatedGET(
      path: "api/history/period/\(interval.start.formatted(style))",
      queryItems: [
        URLQueryItem(name: "end_time", value: interval.end.formatted(style)),
        URLQueryItem(name: "significant_changes_only", value: "0"),
        URLQueryItem(
          name: "filter_entity_id", value: ClimateHistoryZone.entityIDs.joined(separator: ",")),
      ]
    )
    // Home Assistant requires the literal 0 to include position-only cover updates.
    // Attribute-only updates carry temperatures and damper positions. Keep full responses,
    // using last_updated rather than last_changed so these updates retain their timestamps.
    try Task.checkCancellation()
    return try ClimateHistory(data: data, interval: interval)
  }
}
