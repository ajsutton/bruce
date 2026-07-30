extension HomeAssistantHomeEnergyFlowChart {
  var flowAccessibilityDescriptor: HomeEnergyChartAccessibilityDescriptor {
    HomeEnergyChartAccessibilityDescriptor(
      title: copy.flowHistory,
      summary: accessibilitySummary,
      timeAxisTitle: copy.flowHistoryTimeAxis,
      valueAxisTitle: copy.flowHistoryPowerAxis,
      interval: store.flowHistory.interval,
      valueRange: flowYDomain,
      valueDescription: {
        "\($0.formatted(.number.precision(.fractionLength(0...1)))) kilowatts"
      },
      series: HomeEnergyFlowHistory.Series.allCases.flatMap { series in
        let segments =
          store.flowHistory.availableReadingSegments[series] ?? []
        return segments.map { segment in
          HomeEnergyChartAccessibilityDescriptor.Series(
            name: seriesName(for: series),
            points: segment.compactMap { reading in
              reading.kilowatts.map { (reading.timestamp, $0) }
            }
          )
        }
      }
    )
  }

  private var accessibilitySummary: String {
    let summary = "\(copy.flowHistoryPeriod). \(copy.flowHistoryPolarity)."
    guard let freshnessLabel else { return summary }
    return "\(summary) \(freshnessLabel)."
  }
}
