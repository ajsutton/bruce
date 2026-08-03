enum WidgetHomeEnergyError: Error, Equatable, Sendable {
  case credentialsUnavailable
  case invalidResponse
  case noReachableServer
  case unauthorized
}
