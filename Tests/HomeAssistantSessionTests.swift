import XCTest

@testable import Bruce

final class HomeAssistantSessionTests: XCTestCase {
  func testReadUsesBearerOnLastSuccessfulConfirmedInternalURL() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [.success(Data("response".utf8), statusCode: 200)]
    )
    try await session.install(fixture.credentials())

    let data = try await session.authenticatedGET(path: "api/")

    XCTAssertEqual(data, Data("response".utf8))
    let request = try XCTUnwrap(fixture.apiLoader.requests.first)
    XCTAssertEqual(request.url?.host(), "home.local")
    XCTAssertEqual(
      request.value(forHTTPHeaderField: "Authorization"),
      "Bearer access-value"
    )
  }

  func testConnectivityFailureFallsBackOnceAndRemembersExternalURL() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [
        .failure(URLError(.cannotConnectToHost)),
        .success(Data("external".utf8), statusCode: 200),
      ]
    )
    try await session.install(fixture.credentials())

    let data = try await session.authenticatedGET(path: "api/")

    XCTAssertEqual(data, Data("external".utf8))
    XCTAssertEqual(
      fixture.apiLoader.requests.map { $0.url?.host() }, ["home.local", "home.example"])
    let currentCredentials = await session.currentCredentials()
    let storedCredentials = await fixture.store.value
    XCTAssertEqual(currentCredentials?.lastSuccessfulURL, fixture.externalURL)
    XCTAssertEqual(storedCredentials?.lastSuccessfulURL, fixture.externalURL)
  }

  func testHTTPFailureDoesNotFallBack() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [.success(Data(), statusCode: 500)]
    )
    try await session.install(fixture.credentials())

    do {
      _ = try await session.authenticatedGET(path: "api/")
      XCTFail("Expected an HTTP error.")
    } catch HomeAssistantAPIError.server(let statusCode) {
      XCTAssertEqual(statusCode, 500)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    XCTAssertEqual(fixture.apiLoader.requests.count, 1)
  }

  func testHTTPExternalURLIsNeverSentABearerToken() async throws {
    let fixture = SessionFixture()
    let insecureExternal = try XCTUnwrap(URL(string: "http://home.example"))
    let credentials = HomeAssistantCredentials(
      instanceID: "instance",
      instanceName: "Home",
      internalURL: nil,
      externalURL: insecureExternal,
      lastSuccessfulURL: insecureExternal,
      accessToken: "access-value",
      refreshToken: "refresh-value",
      tokenType: "Bearer",
      accessTokenExpiresAt: fixture.future,
      clientID: HomeAssistantOAuthConfiguration.release.clientID
    )
    let session = fixture.makeSession(apiResponses: [])
    try await session.install(credentials)

    do {
      _ = try await session.authenticatedGET(path: "api/")
      XCTFail("Expected the external URL to be rejected.")
    } catch HomeAssistantAPIError.invalidServerURL {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    XCTAssertTrue(fixture.apiLoader.requests.isEmpty)
  }

  func testExpiredTokenRefreshesBeforeRead() async throws {
    let fixture = SessionFixture()
    let tokenResponse = Data(
      """
      {
        "access_token": "refreshed-access",
        "token_type": "Bearer",
        "expires_in": 1800
      }
      """.utf8
    )
    let session = fixture.makeSession(
      apiResponses: [.success(Data("response".utf8), statusCode: 200)],
      authenticationResponses: [
        .success(tokenResponse, statusCode: 200),
        .success(tokenResponse, statusCode: 200),
      ]
    )
    try await session.install(fixture.credentials(expiresAt: fixture.past))

    _ = try await session.authenticatedGET(path: "api/")

    XCTAssertEqual(fixture.authenticationLoader.requests.count, 2)
    XCTAssertEqual(
      fixture.apiLoader.requests.first?.value(forHTTPHeaderField: "Authorization"),
      "Bearer refreshed-access"
    )
  }

  func testUnauthorizedReadRefreshesAndRetriesOnce() async throws {
    let fixture = SessionFixture()
    let tokenResponse = Data(
      """
      {
        "access_token": "refreshed-access",
        "token_type": "Bearer",
        "expires_in": 1800
      }
      """.utf8
    )
    let session = fixture.makeSession(
      apiResponses: [
        .success(Data(), statusCode: 401),
        .success(Data("retried".utf8), statusCode: 200),
      ],
      authenticationResponses: [
        .success(tokenResponse, statusCode: 200),
        .success(tokenResponse, statusCode: 200),
      ]
    )
    try await session.install(fixture.credentials())

    let data = try await session.authenticatedGET(path: "api/")

    XCTAssertEqual(data, Data("retried".utf8))
    XCTAssertEqual(fixture.apiLoader.requests.count, 2)
    XCTAssertEqual(
      fixture.apiLoader.requests.last?.value(forHTTPHeaderField: "Authorization"),
      "Bearer refreshed-access"
    )
  }

  func testRejectedRefreshDeletesCredentialsAndRequiresAuthentication() async throws {
    let fixture = SessionFixture()
    let rejectedResponse = Data(
      """
      {"error": "invalid_grant", "error_description": "Refresh token is invalid"}
      """.utf8
    )
    let session = fixture.makeSession(
      apiResponses: [],
      authenticationResponses: [
        .success(rejectedResponse, statusCode: 400),
        .success(rejectedResponse, statusCode: 400),
      ]
    )
    try await session.install(fixture.credentials(expiresAt: fixture.past))

    do {
      _ = try await session.authenticatedGET(path: "api/")
      XCTFail("Expected reauthentication.")
    } catch HomeAssistantAPIError.reauthenticationRequired {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    let currentCredentials = await session.currentCredentials()
    let storedCredentials = await fixture.store.value
    XCTAssertNil(currentCredentials)
    XCTAssertNil(storedCredentials)
  }

}

final class SessionFixture {
  let internalURL = URL(string: "http://home.local:8123") ?? URL(fileURLWithPath: "/")
  let externalURL = URL(string: "https://home.example") ?? URL(fileURLWithPath: "/")
  let now = Date(timeIntervalSince1970: 10_000)
  var future: Date { now.addingTimeInterval(3_600) }
  var past: Date { now.addingTimeInterval(-1) }

  let store = InMemoryHomeAssistantCredentialStore()
  let apiLoader = QueueHomeAssistantLoader()
  let authenticationLoader = QueueHomeAssistantLoader()

  func makeSession(
    apiResponses: [QueueHomeAssistantLoader.Result],
    authenticationResponses: [QueueHomeAssistantLoader.Result] = []
  ) -> HomeAssistantSession {
    apiLoader.results = apiResponses
    authenticationLoader.results = authenticationResponses
    return HomeAssistantSession(
      credentialStore: store,
      authenticationClient: HomeAssistantAuthenticationClient(
        loader: authenticationLoader,
        now: { [now] in now }
      ),
      loader: apiLoader,
      now: { [now] in now }
    )
  }

  func credentials(expiresAt: Date? = nil) -> HomeAssistantCredentials {
    HomeAssistantCredentials(
      instanceID: "instance",
      instanceName: "Home",
      internalURL: internalURL,
      externalURL: externalURL,
      lastSuccessfulURL: internalURL,
      accessToken: "access-value",
      refreshToken: "refresh-value",
      tokenType: "Bearer",
      accessTokenExpiresAt: expiresAt ?? future,
      clientID: HomeAssistantOAuthConfiguration.release.clientID
    )
  }
}

actor InMemoryHomeAssistantCredentialStore: HomeAssistantCredentialStoring {
  private(set) var value: HomeAssistantCredentials?

  func load() -> HomeAssistantCredentials? {
    value
  }

  func save(_ credentials: HomeAssistantCredentials) {
    value = credentials
  }

  func replace(
    _ credentials: HomeAssistantCredentials?,
    ifCurrentIs original: HomeAssistantCredentials?
  ) -> Bool {
    guard value == original else { return false }
    value = credentials
    return true
  }

  func delete() {
    value = nil
  }
}

final class QueueHomeAssistantLoader: HomeAssistantHTTPDataLoading, @unchecked Sendable {
  enum Result {
    case success(Data, statusCode: Int)
    case failure(any Error)
  }

  private let lock = NSLock()
  private var storedRequests: [URLRequest] = []
  private var storedResults: [Result] = []

  var requests: [URLRequest] {
    lock.withLock { storedRequests }
  }

  var results: [Result] {
    get { lock.withLock { storedResults } }
    set { lock.withLock { storedResults = newValue } }
  }

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let result = lock.withLock { () -> Result? in
      storedRequests.append(request)
      guard !storedResults.isEmpty else {
        return nil
      }
      return storedResults.removeFirst()
    }
    guard let result else {
      throw HomeAssistantAPIError.invalidResponse
    }
    switch result {
    case .failure(let error):
      throw error
    case .success(let data, let statusCode):
      let responseURL = request.url ?? URL(fileURLWithPath: "/")
      guard
        let response = HTTPURLResponse(
          url: responseURL,
          statusCode: statusCode,
          httpVersion: nil,
          headerFields: nil
        )
      else {
        throw HomeAssistantAPIError.invalidResponse
      }
      return (data, response)
    }
  }
}

final class BlockingHomeAssistantLoader: HomeAssistantHTTPDataLoading, @unchecked Sendable {
  private typealias LoaderResult = Result<(Data, HTTPURLResponse), any Error>

  let started = XCTestExpectation(description: "Request started")
  let cancellationObserved = XCTestExpectation(description: "Request cancellation observed")

  private let honorsCancellation: Bool
  private let lock = NSLock()
  private var continuations: [CheckedContinuation<(Data, HTTPURLResponse), any Error>] = []
  private var storedRequests: [URLRequest] = []
  private var completedResult: LoaderResult?
  private var cancellationRequested = false

  var requests: [URLRequest] {
    lock.withLock { storedRequests }
  }

  var wasCancelled: Bool {
    lock.withLock { cancellationRequested }
  }

  init(honorsCancellation: Bool = true) {
    self.honorsCancellation = honorsCancellation
  }

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        let state: (isFirstRequest: Bool, result: LoaderResult?) = lock.withLock {
          let isFirstRequest = storedRequests.isEmpty
          storedRequests.append(request)
          if cancellationRequested {
            return (isFirstRequest, .failure(CancellationError()))
          }
          if let completedResult {
            return (isFirstRequest, completedResult)
          }
          continuations.append(continuation)
          return (isFirstRequest, nil)
        }
        if state.isFirstRequest {
          started.fulfill()
        }
        if let result = state.result {
          continuation.resume(with: result)
        }
      }
    } onCancel: {
      let continuations: [CheckedContinuation<(Data, HTTPURLResponse), any Error>] =
        self.lock.withLock {
          let shouldReportCancellation = !self.cancellationRequested
          self.cancellationRequested = true
          if shouldReportCancellation {
            self.cancellationObserved.fulfill()
          }
          guard self.honorsCancellation else {
            return []
          }
          let continuations = self.continuations
          self.continuations.removeAll()
          return continuations
        }
      continuations.forEach { $0.resume(throwing: CancellationError()) }
    }
  }

  func succeed(with data: Data, statusCode: Int) {
    let result: LoaderResult
    if let requestURL = requests.first?.url,
      let response = HTTPURLResponse(
        url: requestURL,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: nil
      )
    {
      result = .success((data, response))
    } else {
      result = .failure(HomeAssistantAPIError.invalidResponse)
    }
    let continuations = lock.withLock {
      completedResult = result
      let continuations = self.continuations
      self.continuations.removeAll()
      return continuations
    }
    continuations.forEach { $0.resume(with: result) }
  }
}
