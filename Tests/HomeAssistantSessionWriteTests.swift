import XCTest

@testable import Bruce

final class HomeAssistantSessionWriteTests: XCTestCase {
  func testUnauthorizedWriteRefreshesAndRetriesWithOriginalBody() async throws {
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
    let body = Data(#"{"entity_id":"climate.house"}"#.utf8)

    let data = try await session.authenticatedPOST(
      path: "api/services/climate/turn_on",
      body: body
    )

    XCTAssertEqual(data, Data("retried".utf8))
    XCTAssertEqual(fixture.apiLoader.requests.map(\.httpMethod), ["POST", "POST"])
    XCTAssertEqual(fixture.apiLoader.requests.map(\.httpBody), [body, body])
    XCTAssertEqual(
      fixture.apiLoader.requests.last?.value(forHTTPHeaderField: "Authorization"),
      "Bearer refreshed-access"
    )
  }

  func testDelayedUnauthorizedWriteUsesTokenRefreshedByConcurrentWrite() async throws {
    let fixture = SessionFixture()
    let loader = OrderedBlockingHomeAssistantLoader(requestCount: 4)
    let tokenResponse = Data(
      """
      {
        "access_token": "refreshed-access",
        "token_type": "Bearer",
        "expires_in": 1800
      }
      """.utf8
    )
    fixture.authenticationLoader.results = [
      .success(tokenResponse, statusCode: 200),
      .success(tokenResponse, statusCode: 200),
    ]
    let session = makeSession(fixture: fixture, loader: loader)
    try await session.install(fixture.credentials())
    let firstWrite = Task {
      try await session.authenticatedPOST(
        path: "api/services/climate/turn_on",
        body: Data("first".utf8)
      )
    }
    await fulfillment(of: [loader.started(at: 0)], timeout: 1)
    let secondWrite = Task {
      try await session.authenticatedPOST(
        path: "api/services/climate/turn_on",
        body: Data("second".utf8)
      )
    }
    await fulfillment(of: [loader.started(at: 1)], timeout: 1)

    loader.complete(request: 0, data: Data(), statusCode: 401)
    await fulfillment(of: [loader.started(at: 2)], timeout: 1)
    loader.complete(request: 2, data: Data("first-complete".utf8), statusCode: 200)
    let firstResponse = try await firstWrite.value
    XCTAssertEqual(firstResponse, Data("first-complete".utf8))

    loader.complete(request: 1, data: Data(), statusCode: 401)
    await fulfillment(of: [loader.started(at: 3)], timeout: 1)
    loader.complete(request: 3, data: Data("second-complete".utf8), statusCode: 200)

    let secondResponse = try await secondWrite.value
    XCTAssertEqual(secondResponse, Data("second-complete".utf8))
    XCTAssertEqual(fixture.authenticationLoader.requests.count, 2)
    XCTAssertEqual(
      loader.requests[3].value(forHTTPHeaderField: "Authorization"),
      "Bearer refreshed-access"
    )
  }

  func testWriteDoesNotRetryAfterCredentialsAreReplacedDuringUnauthorizedResponse() async throws {
    let fixture = SessionFixture()
    let loader = BlockingHomeAssistantLoader(honorsCancellation: false)
    let session = makeSession(fixture: fixture, loader: loader)
    try await session.install(fixture.credentials())
    let write = Task {
      try await session.authenticatedPOST(
        path: "api/services/climate/turn_on",
        body: Data()
      )
    }
    await fulfillment(of: [loader.started], timeout: 1)
    var replacement = fixture.credentials()
    replacement.accessToken = "replacement-access"
    replacement.refreshToken = "replacement-refresh"

    try await session.install(replacement)
    loader.succeed(with: Data(), statusCode: 401)

    do {
      _ = try await write.value
      XCTFail("Expected the old write to become stale.")
    } catch HomeAssistantAPIError.staleOperation {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    XCTAssertEqual(loader.requests.count, 1)
    XCTAssertTrue(fixture.authenticationLoader.requests.isEmpty)
    let currentCredentials = await session.currentCredentials()
    XCTAssertEqual(currentCredentials, replacement)
  }

  func testWriteDoesNotFallBackAfterAmbiguousConnectivityFailure() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [.failure(URLError(.timedOut))]
    )
    try await session.install(fixture.credentials())

    do {
      _ = try await session.authenticatedPOST(
        path: "api/services/climate/turn_on",
        body: Data()
      )
      XCTFail("Expected the timed-out write to fail.")
    } catch let error as URLError {
      XCTAssertEqual(error.code, .timedOut)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    XCTAssertEqual(fixture.apiLoader.requests.count, 1)
  }

  func testConfirmedWriteSucceedsAfterCredentialsChange() async throws {
    let fixture = SessionFixture()
    let loader = BlockingHomeAssistantLoader(honorsCancellation: false)
    let session = makeSession(fixture: fixture, loader: loader)
    try await session.install(fixture.credentials())
    let write = Task {
      try await session.authenticatedPOST(
        path: "api/services/climate/turn_on",
        body: Data()
      )
    }
    await fulfillment(of: [loader.started], timeout: 1)
    var replacement = fixture.credentials()
    replacement.accessToken = "replacement-access"
    replacement.refreshToken = "replacement-refresh"

    try await session.install(replacement)
    loader.succeed(with: Data("confirmed".utf8), statusCode: 200)

    let response = try await write.value
    XCTAssertEqual(response, Data("confirmed".utf8))
    let currentCredentials = await session.currentCredentials()
    XCTAssertEqual(currentCredentials, replacement)
  }

  private func makeSession(
    fixture: SessionFixture,
    loader: any HomeAssistantHTTPDataLoading
  ) -> HomeAssistantSession {
    HomeAssistantSession(
      credentialStore: fixture.store,
      authenticationClient: HomeAssistantAuthenticationClient(
        loader: fixture.authenticationLoader,
        now: { [now = fixture.now] in now }
      ),
      loader: loader,
      now: { [now = fixture.now] in now }
    )
  }
}

private final class OrderedBlockingHomeAssistantLoader:
  HomeAssistantHTTPDataLoading, @unchecked Sendable
{
  private let lock = NSLock()
  private let startedExpectations: [XCTestExpectation]
  private var continuations: [Int: CheckedContinuation<(Data, HTTPURLResponse), any Error>] = [:]
  private var storedRequests: [URLRequest] = []

  init(requestCount: Int) {
    startedExpectations = (0..<requestCount).map {
      XCTestExpectation(description: "HTTP request \($0) started")
    }
  }

  var requests: [URLRequest] {
    lock.withLock { storedRequests }
  }

  func started(at index: Int) -> XCTestExpectation {
    startedExpectations[index]
  }

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    try await withCheckedThrowingContinuation { continuation in
      let index = lock.withLock {
        let index = storedRequests.count
        storedRequests.append(request)
        continuations[index] = continuation
        return index
      }
      startedExpectations[index].fulfill()
    }
  }

  func complete(request index: Int, data: Data, statusCode: Int) {
    let state = lock.withLock {
      (continuations.removeValue(forKey: index), storedRequests[index])
    }
    guard
      let response = HTTPURLResponse(
        url: state.1.url ?? URL(fileURLWithPath: "/"),
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: nil
      )
    else {
      state.0?.resume(throwing: HomeAssistantAPIError.invalidResponse)
      return
    }
    state.0?.resume(returning: (data, response))
  }
}
