import Foundation

protocol HomeAssistantHTTPDataLoading: Sendable {
  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionHomeAssistantHTTPDataLoader: HomeAssistantHTTPDataLoading {
  private let session: URLSession

  init(session: URLSession? = nil) {
    self.session =
      session
      ?? URLSession(
        configuration: .default,
        delegate: HomeAssistantRedirectDelegate(),
        delegateQueue: nil
      )
  }

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let (data, response) = try await session.data(for: request)
    guard let response = response as? HTTPURLResponse else {
      throw HomeAssistantAuthenticationError.unexpectedResponse
    }
    return (data, response)
  }
}

private final class HomeAssistantRedirectDelegate: NSObject, URLSessionTaskDelegate,
  @unchecked Sendable
{
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    guard let originalURL = response.url, let redirectedURL = request.url,
      HomeAssistantRedirectPolicy.allowsRedirect(from: originalURL, to: redirectedURL)
    else {
      completionHandler(nil)
      return
    }
    completionHandler(request)
  }

}
