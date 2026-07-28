import Foundation

enum RouteSelection: Sendable {
  case ordered
  case firstValid(@Sendable (Data) throws -> Void)
}
