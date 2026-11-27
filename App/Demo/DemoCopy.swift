import Foundation

struct DemoCopy {
  let mode: BruceMode

  private func text(_ key: String.LocalizationValue) -> String {
    BruceCopy(mode: mode).text(.localized(key))
  }

  var title: String { text("demo.title") }
  var launch: String { text("demo.launch") }
  var exit: String { text("demo.exit") }
  var disclosure: String { text("demo.disclosure") }
  var launchHint: String { text("demo.launchHint") }
  var finishVoiceHint: String { text("demo.finishVoiceHint") }
  var unmuteHint: String { text("demo.unmuteHint") }
  var sampleQuestions: String { text("demo.sampleQuestions") }
  var homeQuestion: String { text("demo.homeQuestion") }
  var voiceQuestion: String { text("demo.voiceQuestion") }
  var coolLounge: String { text("demo.coolLounge") }
  var welcome: String { text("demo.welcome") }
  var temperatureChanged: String { text("demo.temperatureChanged") }
  var temperatureFailed: String { text("demo.temperatureFailed") }
  var voiceExplanation: String { text("demo.voiceExplanation") }
  var houseAgent: String { text("demo.houseAgent") }
  var familyAgent: String { text("demo.familyAgent") }

  func homeDescription(temperature: Double, target: Double) -> String {
    String(
      format: text("demo.homeDescription"),
      temperature.formatted(), target.formatted()
    )
  }
}
