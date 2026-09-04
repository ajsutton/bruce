import Foundation

protocol WidgetEnergyWebSocketConnection: Sendable {
  func resume()
  func send(_ data: Data) async throws
  func receive() async throws -> Data
  func cancel()
}

final class URLSessionWidgetEnergyWebSocket:
  WidgetEnergyWebSocketConnection,
  @unchecked Sendable
{
  private let task: URLSessionWebSocketTask
  private let lock = NSLock()
  private var isCancelled = false

  init(task: URLSessionWebSocketTask) {
    self.task = task
  }

  func resume() {
    task.resume()
  }

  func send(_ data: Data) async throws {
    try await task.send(.data(data))
  }

  func receive() async throws -> Data {
    switch try await task.receive() {
    case .data(let data): data
    case .string(let string): Data(string.utf8)
    @unknown default: throw WidgetHomeEnergyError.invalidResponse
    }
  }

  func cancel() {
    let shouldCancel = lock.withLock {
      guard !isCancelled else { return false }
      isCancelled = true
      return true
    }
    if shouldCancel {
      task.cancel(with: .goingAway, reason: nil)
    }
  }
}

struct WidgetEnergyMessageKind: Decodable {
  let type: String
}

struct WidgetEnergyAuthentication: Encodable {
  let type: String
  let accessToken: String

  enum CodingKeys: String, CodingKey {
    case type
    case accessToken = "access_token"
  }
}

struct WidgetEnergyTotalRequest: Encodable {
  let id: Int
  let type: String
  let startTime: String
  let endTime: String
  let statisticID: String
  let types: [String]

  enum CodingKeys: String, CodingKey {
    case id, type, types
    case startTime = "start_time"
    case endTime = "end_time"
    case statisticID = "statistic_id"
  }
}

struct WidgetEnergyTotalResponse: Decodable {
  struct Result: Decodable {
    let change: Double?
  }

  let id: Int
  let type: String
  let success: Bool
  let result: Result?
}

struct WidgetEnergyStatisticsRequest: Encodable {
  let id: Int
  let type: String
  let startTime: String
  let endTime: String
  let statisticIDs: [String]
  let period: String
  let types: [String]

  enum CodingKeys: String, CodingKey {
    case id, type, period, types
    case startTime = "start_time"
    case endTime = "end_time"
    case statisticIDs = "statistic_ids"
  }
}

struct WidgetEnergyStatisticsResponse: Decodable {
  let id: Int
  let type: String
  let success: Bool
  let result: [String: [WidgetEnergyStatistic]]?
}

struct WidgetEnergyStatistic: Decodable {
  let start: Date
  let end: Date
  let state: Double?

  enum CodingKeys: String, CodingKey {
    case start, end, state
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    start = Date(
      timeIntervalSince1970: try container.decode(Double.self, forKey: .start) / 1_000
    )
    end = Date(
      timeIntervalSince1970: try container.decode(Double.self, forKey: .end) / 1_000
    )
    state = try container.decodeIfPresent(Double.self, forKey: .state)
  }
}
