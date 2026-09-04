import Foundation

final class SequencedWidgetClock: @unchecked Sendable {
  private let lock = NSLock()
  private var dates: [Date]

  init(_ dates: [Date]) {
    self.dates = dates
  }

  func next() -> Date {
    lock.withLock { dates.removeFirst() }
  }
}
