struct RollingEnergyMetricFlags {
  var importCost = false
  var feedInEarnings = false

  var hasAny: Bool {
    importCost || feedInEarnings
  }
}
