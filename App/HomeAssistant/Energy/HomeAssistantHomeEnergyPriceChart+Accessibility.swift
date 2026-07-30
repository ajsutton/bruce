extension HomeAssistantHomeEnergyPriceChart {
  var priceAccessibilityDescriptor: HomeEnergyChartAccessibilityDescriptor {
    HomeEnergyChartAccessibilityDescriptor(
      title: copy.priceHistory,
      summary: accessibilitySummary,
      timeAxisTitle: copy.priceHistoryTimeAxis,
      valueAxisTitle: copy.priceHistoryPriceAxis,
      interval: store.priceHistory.interval,
      valueRange: priceYDomain,
      valueDescription: {
        "\($0.formatted(.number.precision(.fractionLength(0...1))))¢"
      },
      series: HomeEnergyPriceHistory.Tariff.allCases.flatMap { tariff in
        let segments =
          store.priceHistory.availableReadingSegments[tariff] ?? []
        return segments.map { segment in
          HomeEnergyChartAccessibilityDescriptor.Series(
            name: seriesName(for: tariff),
            points: segment.compactMap { reading in
              reading.centsPerKilowattHour.map {
                (reading.timestamp, $0)
              }
            }
          )
        }
      }
    )
  }

  private var accessibilitySummary: String {
    guard let freshnessLabel else { return copy.priceHistoryPeriod }
    return "\(copy.priceHistoryPeriod). \(freshnessLabel)."
  }
}
