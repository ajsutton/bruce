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
      shortTitle: "Solar Generation",
      systemImageName: "sun.max"
    )
    AppShortcut(
      intent: GetHomeBatteryLevelIntent(),
      phrases: [
        "What’s the current battery level in \(.applicationName)",
        "What’s the home battery level in \(.applicationName)",
      ],
      shortTitle: "Home Battery Level",
      systemImageName: "battery.100percent"
    )
    AppShortcut(
      intent: GetElectricityUsageIntent(),
      phrases: [
        "What’s the current electricity usage in \(.applicationName)",
        "How much power is the house using in \(.applicationName)",
      ],
      shortTitle: "Electricity Usage",
      systemImageName: "bolt"
    )
    AppShortcut(
      intent: GetEVChargerModeIntent(),
      phrases: ["What’s the EV charger mode in \(.applicationName)"],
      shortTitle: "EV Charger Mode",
      systemImageName: "bolt.car"
    )
    AppShortcut(
      intent: GetEVChargerStatusIntent(),
      phrases: [
        "What’s the EV charger status in \(.applicationName)",
        "Is the car charging in \(.applicationName)",
      ],
      shortTitle: "EV Charger Status",
      systemImageName: "ev.charger"
    )
    AppShortcut(
      intent: SetEVChargerModeIntent(),
      phrases: [
        "Set the EV charger in \(.applicationName) to \(\.$mode)",
        "Set the EV charger mode in \(.applicationName)",
      ],
      shortTitle: "Set EV Charger Mode",
      systemImageName: "bolt.car"
    )
  }
}
