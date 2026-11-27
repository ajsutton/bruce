import Combine
import Foundation

/// A demo visit owns separate clients and stores; nothing is saved to the user's home or Keychain.
@MainActor
final class DemoSession: ObservableObject {
  let climate = DemoClimate()
  let temperatureStore: HomeAssistantTemperatureStore
  let chargingStore: HomeAssistantEVChargingStore
  let garageDoorStore: HomeAssistantGarageDoorStore
  let homeEnergyStore: HomeAssistantHomeEnergyStore
  let voiceStore: OpenClawVoiceStore
  private let audio = DemoVoiceAudio()
  private let copy: DemoCopy

  init(mode: BruceMode = .standard) {
    copy = DemoCopy(mode: mode)
    temperatureStore = HomeAssistantTemperatureStore(
      loader: climate, controller: climate,
      historyStore: ClimateHistoryStore(source: climate, loader: climate)
    )
    chargingStore = HomeAssistantEVChargingStore(client: DemoCharger())
    let garage = DemoGarage()
    garageDoorStore = HomeAssistantGarageDoorStore(loader: garage, controller: garage)
    let energy = DemoEnergy()
    homeEnergyStore = HomeAssistantHomeEnergyStore(loader: energy)
    voiceStore = OpenClawVoiceStore(
      client: DemoVoiceClient(mode: mode), systemCall: DemoSystemCall(),
      makeAudio: { [audio] in audio }
    )
  }

  func observe() async {
    async let temperatures: Void = temperatureStore.load()
    async let charging: Void = chargingStore.observeUpdates()
    async let garage: Void = garageDoorStore.observeUpdates()
    await homeEnergyStore.load()
    if !Task.isCancelled { homeEnergyStore.reloadHistory() }
    _ = await (temperatures, charging, garage)
    temperatureStore.reset()
    garageDoorStore.reset()
    await chargingStore.synchronize(with: .signedOut)
    await homeEnergyStore.reset()?.value
  }

  func stopVoice() {
    voiceStore.end(returnToPicker: false)
  }

  func describeHome() {
    guard let room = temperatureStore.readings.first(where: { $0.id == "climate.lounge" }),
      let temperature = room.value, let target = room.targetValue
    else { return }
    audio.speak(copy.homeDescription(temperature: temperature, target: target))
  }

  func coolLounge() async {
    guard voiceStore.phase == .connected, !voiceStore.isMuted else { return }
    do {
      try await climate.setTargetValue(22, entityID: "climate.lounge")
      try Task.checkCancellation()
      guard voiceStore.phase == .connected else { return }
      audio.speak(copy.temperatureChanged)
    } catch is CancellationError {
      return
    } catch {
      audio.speak(copy.temperatureFailed)
    }
  }

  func describeVoice() {
    audio.speak(copy.voiceExplanation)
  }
}
