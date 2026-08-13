import Foundation

struct HomeAssistantConnectionRetryPolicy: Sendable {
  private let initialWindow: TimeInterval
  private let maximumWindow: TimeInterval
  private let randomUnit: @Sendable () -> Double

  init(
    initialWindow: TimeInterval = 5,
    maximumWindow: TimeInterval = 60,
    randomUnit: @escaping @Sendable () -> Double = { Double.random(in: 0...1) }
  ) {
    self.initialWindow = initialWindow
    self.maximumWindow = maximumWindow
    self.randomUnit = randomUnit
  }

  func delay(afterFailure failureCount: Int) -> Duration {
    let exponent = min(max(failureCount - 1, 0), 20)
    let window = min(initialWindow * pow(2, Double(exponent)), maximumWindow)
    let unit = min(max(randomUnit(), 0), 1)
    return .milliseconds(Int64((window * unit * 1_000).rounded()))
  }
}
