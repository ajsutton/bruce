import Foundation

enum HomeAssistantAPIError: Error {
  case noCredentials
  case invalidServerURL
  case unauthorized
  case reauthenticationRequired
  case incompatibleServer
  case server(statusCode: Int)
  case invalidResponse
  case staleOperation
}
