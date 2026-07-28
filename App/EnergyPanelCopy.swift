struct EnergyPanelCopy {
  private let copy: BruceCopy

  init(mode: BruceMode) {
    copy = BruceCopy(mode: mode)
  }

  var navigationTitle: String {
    copy.text(.localized("energyPanel.navigationTitle"))
  }
}
