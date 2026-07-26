import Foundation

struct HomeAssistantCopy {
  let mode: BruceMode

  var navigationTitle: String {
    "Home Assistant"
  }

  var introductionTitle: String {
    mode.isFullBruce ? "Let’s Find the Joint" : "Find Your Home"
  }

  var introductionDescription: String {
    if mode.isFullBruce {
      "Bruce can have a look around the local network for Home Assistant, or you can point him at the address."
    } else {
      "Bruce can look on your local network for Home Assistant. You can also enter its address yourself."
    }
  }

  var searching: String {
    mode.isFullBruce ? "Having a look for Home Assistant…" : "Looking for Home Assistant…"
  }

  var noHomesFound: String {
    mode.isFullBruce ? "No homes turned up" : "No homes found"
  }

  var searchingFooter: String {
    mode.isFullBruce
      ? "Bruce keeps having a look while this screen is open."
      : "Bruce keeps looking while this screen is open."
  }

  var searchInactive: String {
    mode.isFullBruce ? "The search is parked." : "Search is not active."
  }

  var findHomeAssistant: String {
    mode.isFullBruce ? "Have a Look for Home Assistant" : "Find Home Assistant"
  }

  var enterAddressManually: String {
    mode.isFullBruce ? "Put the Address In" : "Enter Address Manually"
  }

  var searchAgain: String {
    mode.isFullBruce ? "Have Another Look" : "Search Again"
  }

  var chooseAnotherServer: String {
    mode.isFullBruce ? "Pick Another Home" : "Choose Another Server"
  }

  var recoveryChooseAnotherServer: String {
    "Choose Another Server"
  }

  var startAgain: String {
    mode.isFullBruce ? "Give It Another Go" : "Start Again"
  }

  var chooseDiscoveredHome: String {
    mode.isFullBruce ? "Pick a Home Bruce Found" : "Choose a Discovered Home"
  }

  var manageConnection: String {
    mode.isFullBruce ? "Sort Out Connection" : "Manage Connection"
  }

  var testConnection: String {
    mode.isFullBruce ? "Give Connection a Test" : "Test Connection"
  }

  var changeServer: String {
    mode.isFullBruce ? "Pick Another Server" : "Change Server"
  }

  var setUpHomeAssistant: String {
    mode.isFullBruce ? "Sort Out Home Assistant" : "Set Up Home Assistant"
  }

  func connectedTitle(instanceName: String) -> String {
    mode.isFullBruce ? "\(instanceName) is sorted" : "Connected to \(instanceName)"
  }

  var connectionIdle: String {
    mode.isFullBruce
      ? "Bruce will give both saved addresses a go automatically."
      : "Bruce will automatically try the saved internal and external addresses."
  }

  var connectionChecking: String {
    "Checking the Home Assistant connection…"
  }

  var connectionSucceeded: String {
    mode.isFullBruce ? "Connection’s good as gold." : "Connection verified."
  }

  var setupCancelledTitle: String {
    mode.isFullBruce ? "Setup Parked for Now" : "Setup Cancelled"
  }

  var notConnected: String {
    mode.isFullBruce ? "Home Assistant isn’t sorted yet" : "Not connected"
  }

  var connectedStatus: String {
    mode.isFullBruce ? "Good as gold" : "Connected"
  }

  func configuredTitle(instanceName: String) -> String {
    "Home Assistant is configured for \(instanceName)"
  }

  // Permission, authentication, transport-security, recovery, and destructive copy intentionally
  // stays identical between modes under the brand safety boundary.
  var restoringTitle: String {
    "Restoring Connection"
  }

  var restoringDetail: String {
    "Checking your saved Home Assistant connection."
  }

  var localNetworkAccessOff: String {
    "Local Network Access Is Off"
  }

  var discoveryFailed: String {
    "Bruce Couldn’t Search the Network"
  }

  var unencryptedTitle: String {
    "Connection Isn’t Encrypted"
  }

  var unencryptedMessage: String {
    "This HTTP address can expose your Home Assistant sign-in on the local network. Continue only if you trust this network."
  }

  var onboardingTitle: String {
    "Finish Setting Up Home Assistant"
  }

  func onboardingMessage(instanceName: String) -> String {
    "\(instanceName) hasn’t finished its own setup yet. Complete that in Home Assistant, then try again."
  }

  var openingHomeAssistant: String {
    "Opening Home Assistant"
  }

  func authenticationHandoff(instanceName: String) -> String {
    "Sign in to \(instanceName) in the system browser window."
  }

  func connectionFailed(_ problem: HomeAssistantSetupStore.ConnectionCheckProblem) -> String {
    switch problem {
    case .networkUnavailable:
      "Bruce could not reach Home Assistant. Check the network and server address, then try again."
    case .serverRejectedRequest:
      "Home Assistant responded with an error. Check the server, then try again."
    case .incompatibleServer:
      "This address doesn’t appear to be a Home Assistant server. Check the server address, then try again."
    case .invalidResponse:
      "Home Assistant returned a response Bruce could not read. Try again."
    case .other:
      "The Home Assistant connection check failed. Try again or sign in again."
    }
  }

  func connectionFailedStatus(
    _ problem: HomeAssistantSetupStore.ConnectionCheckProblem
  ) -> String {
    switch problem {
    case .networkUnavailable:
      "Home Assistant could not be reached"
    case .serverRejectedRequest:
      "Home Assistant returned an error"
    case .incompatibleServer:
      "Address is not a Home Assistant server"
    case .invalidResponse:
      "Invalid Home Assistant response"
    case .other:
      "Connection check failed"
    }
  }

  var reauthenticationRequired: String {
    "Home Assistant requires you to sign in again."
  }

  var disconnectFailed: String {
    "The saved Home Assistant connection was not removed and remains active. Try disconnecting again."
  }

  var restoreFailedTitle: String {
    "Saved Connection Couldn’t Be Loaded"
  }

  var restoreFailedMessage: String {
    "Bruce could not read the saved Home Assistant connection securely."
  }

  var settingsRestoreFailed: String {
    "The saved Home Assistant connection could not be loaded."
  }

  func authenticationTitle(
    _ problem: HomeAssistantSetupStore.AuthenticationProblem
  ) -> String {
    switch problem {
    case .rejected:
      "Home Assistant Didn’t Approve Sign-In"
    case .inactiveUser:
      "Home Assistant User Is Inactive"
    case .browserUnavailable:
      "Sign-In Window Didn’t Open"
    case .browserSessionEnded:
      "Sign-In Didn’t Complete"
    case .unavailable:
      "Home Assistant Is Unavailable"
    case .invalidCallback:
      "Sign-In Couldn’t Be Verified"
    case .verificationFailed:
      "Connection Check Failed"
    case .couldNotSave:
      "Connection Couldn’t Be Saved"
    case .other:
      "Couldn’t Connect to Home Assistant"
    }
  }

  func authenticationMessage(
    _ problem: HomeAssistantSetupStore.AuthenticationProblem
  ) -> String {
    switch problem {
    case .rejected:
      "Sign in again and approve Bruce in Home Assistant."
    case .inactiveUser:
      "Activate this user in Home Assistant, then try again."
    case .browserUnavailable:
      "Bruce could not open the sign-in window. Try again. If it still doesn’t open, quit and reopen Bruce."
    case .browserSessionEnded:
      "The sign-in window either couldn’t open or closed before Home Assistant returned to Bruce. Try again when you’re ready."
    case .unavailable:
      "Check that the server is running and that this device can reach it."
    case .invalidCallback:
      "The sign-in response did not match this request. Start sign-in again."
    case .verificationFailed:
      "Sign-in finished, but Bruce could not verify the Home Assistant API."
    case .couldNotSave:
      "Bruce could not store the connection securely. Try again."
    case .other:
      "Try again, or choose a different Home Assistant server."
    }
  }

  func manualValidationMessage(
    _ error: HomeAssistantServerAddress.ValidationError
  ) -> String {
    switch error {
    case .empty:
      "Enter your Home Assistant address."
    case .unsupportedScheme:
      "Use an HTTP or HTTPS address."
    case .missingHost:
      "Enter a complete server address."
    case .containsCredentials:
      "Remove the username and password from the address."
    case .containsQuery:
      "Remove everything after the question mark."
    case .containsFragment:
      "Remove everything after the number sign."
    case .pointsToEndpoint:
      "Enter the server’s base address, not an API or sign-in page."
    }
  }
}

extension HomeAssistantCopy {
  func connectionCheckAnnouncement(
    _ state: HomeAssistantSetupStore.ConnectionCheckState
  ) -> String? {
    switch state {
    case .idle:
      nil
    case .checking:
      "Checking the Home Assistant connection."
    case .succeeded:
      "The Home Assistant connection check succeeded."
    case .failed(let problem):
      connectionFailed(problem)
    case .reauthenticationRequired:
      reauthenticationRequired
    case .disconnectFailed:
      disconnectFailed
    }
  }
}
