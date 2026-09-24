import SwiftUI

#Preview("Zone history · compact") {
  ClimateHistoryPreview(mode: .standard)
    .frame(width: 360)
}

#Preview("Zone history · Full Bruce") {
  ClimateHistoryPreview(mode: .full)
    .frame(width: 640)
    .preferredColorScheme(.dark)
}

#Preview("Zone history · large text") {
  ClimateHistoryPreview(mode: .standard)
    .frame(width: 360)
    .environment(\.dynamicTypeSize, .accessibility2)
}

private struct ClimateHistoryPreview: View {
  let mode: BruceMode
  private let end = Date(timeIntervalSince1970: 1_790_208_000)

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(ClimateHistoryCopy(mode: mode).title).font(.title2.bold())
      Text("Lounge").font(.headline)
      ClimateHistoryChart(
        zone: ClimateHistoryZone.all[0], points: points,
        interval: DateInterval(start: end.addingTimeInterval(-12 * 3600), end: end),
        unit: "°C", mode: mode, isStale: false
      )
    }
    .padding(20)
    .background(.background)
  }

  private var points: [ClimateHistoryPoint] {
    (0...48).map { index in
      let isOn = (12...35).contains(index)
      return ClimateHistoryPoint(
        timestamp: end.addingTimeInterval(Double(index - 48) * 900),
        value: ClimateHistoryValue(
          actual: index == 40
            ? nil
            : 24 - Double(min(max(index - 12, 0), 24)) * 0.12 + Double(max(index - 36, 0)) * 0.08,
          target: index < 12 ? 24 : 21,
          opening: isOn ? Double(100 - max(index - 18, 0) * 4) : 0,
          activity: isOn ? .active : .off
        )
      )
    }
  }
}
