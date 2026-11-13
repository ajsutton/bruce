import Foundation

struct OpenClawTalkSession: Decodable, Sendable {
  struct Control: Decodable, Sendable { let owner: String }
  let voiceSessionId: String
  let clientSecret: String
  let offerUrl: String
  let clientControl: Control?
  let transport: String

  func offerRequest(origin: CloudflareAccessOrigin, access: CloudflareAccessSession, sdp: String)
    throws -> URLRequest
  {
    guard transport == "webrtc", clientControl?.owner == "gateway",
      let url = URL(string: offerUrl, relativeTo: origin.url)?.absoluteURL,
      origin.contains(url), let accessToken = access.authorizationHeader(for: url)
    else { throw OpenClawVoiceError.unavailable }
    var request = URLRequest(url: url, timeoutInterval: 30)
    request.httpMethod = "POST"
    request.setValue("application/sdp", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(clientSecret)", forHTTPHeaderField: "Authorization")
    request.setValue(accessToken, forHTTPHeaderField: "Cf-Access-Token")
    request.setValue(CloudflareAccessClient.userAgent, forHTTPHeaderField: "User-Agent")
    request.httpBody = Data(sdp.utf8)
    return request
  }
}
