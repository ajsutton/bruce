import AppIntents

struct BruceAppShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: GetSolarGenerationIntent(),
      phrases: [
        "What’s the current solar generation in \(.applicationName)",
        "What’s the current PV generation in \(.applicationName)",
        "How much solar power am I generating in \(.applicationName)",
      ],
      shortTitle: "siri.solar.shortTitle",
      systemImageName: "sun.max"
    )
    AppShortcut(
      intent: GetHomeBatteryLevelIntent(),
      phrases: [
        "What’s the current battery level in \(.applicationName)",
        "What’s the home battery level in \(.applicationName)",
      ],
      shortTitle: "siri.battery.shortTitle",
      systemImageName: "battery.100percent"
    )
    AppShortcut(
      intent: GetElectricityUsageIntent(),
      phrases: [
        "What’s the current electricity usage in \(.applicationName)",
        "How much power is the house using in \(.applicationName)",
      ],
      shortTitle: "siri.usage.shortTitle",
      systemImageName: "bolt"
    )
    AppShortcut(
      intent: GetEVChargerModeIntent(),
      phrases: ["What’s the EV charger mode in \(.applicationName)"],
      shortTitle: "siri.mode.shortTitle",
      systemImageName: "bolt.car"
    )
    AppShortcut(
      intent: GetEVChargerStatusIntent(),
      phrases: [
        "What’s the EV charger status in \(.applicationName)",
        "Is the car charging in \(.applicationName)",
      ],
      shortTitle: "siri.status.shortTitle",
      systemImageName: "ev.charger"
    )
    AppShortcut(
      intent: SetEVChargerModeIntent(),
      phrases: [
        "Set the EV charger in \(.applicationName) to \(\.$mode)",
        "Set the EV charger mode in \(.applicationName)",
      ],
      shortTitle: "siri.setMode.shortTitle",
      systemImageName: "bolt.car"
    )
  }
}
