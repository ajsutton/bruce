import Foundation

struct HomeAssistantAuthenticationFailure: Equatable {
  let problem: HomeAssistantSetupStore.AuthenticationProblem
  let diagnostic: String

  init(error: any Error) {
    problem = HomeAssistantAuthenticationProblemMapper.problem(for: error)
    let nsError = error as NSError
    let description = nsError.localizedDescription
    if description.contains(nsError.domain) {
      diagnostic = description
    } else {
      diagnostic = "\(description) (\(nsError.domain), code \(nsError.code))"
    }
  }
}
