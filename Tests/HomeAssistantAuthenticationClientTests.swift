import XCTest

@testable import Bruce

final class HomeAssistantAuthenticationClientTests: XCTestCase {
  func testAuthorizationRequestUsesPermanentIdentityAndInjectedState() throws {
    let client = HomeAssistantAuthenticationClient(stateGenerator: { "fixed-state" })

    let request = try client.authorizationRequest(
      for: try XCTUnwrap(URL(string: "http://home.local:8123/base"))
    )
    let components = try XCTUnwrap(
      URLComponents(url: request.url, resolvingAgainstBaseURL: false)
    )

    XCTAssertEqual(components.path, "/base/auth/authorize")
    XCTAssertEqual(
      Dictionary(
        uniqueKeysWithValues: components.queryItems?.map { ($0.name, $0.value) } ?? []
      ),
      [
        "response_type": "code",
        "client_id": "https://bruce.symphonious.net/",
        "redirect_uri": "https://bruce.symphonious.net/auth/",
        "state": "fixed-state",
      ]
    )
    XCTAssertEqual(request.state, "fixed-state")
  }

  func testCallbackRequiresExactRedirectAndState() throws {
    let client = HomeAssistantAuthenticationClient()
    let callback = try XCTUnwrap(
      URL(string: "https://bruce.symphonious.net/auth/?code=sample-code&state=expected")
    )

    XCTAssertEqual(
      try client.authorizationCode(from: callback, expectedState: "expected"),
      "sample-code"
    )
    XCTAssertThrowsError(
      try client.authorizationCode(from: callback, expectedState: "different")
    ) { error in
      XCTAssertEqual(error as? HomeAssistantAuthenticationError, .stateMismatch)
    }

    let wrongPath = try XCTUnwrap(
      URL(string: "https://bruce.symphonious.net/other/?code=sample-code&state=expected")
    )
    XCTAssertThrowsError(
      try client.authorizationCode(from: wrongPath, expectedState: "expected")
    ) { error in
      XCTAssertEqual(error as? HomeAssistantAuthenticationError, .invalidCallback)
    }
  }

  func testCallbackReportsRejectionAndMissingCode() throws {
    let client = HomeAssistantAuthenticationClient()
    let rejected = try XCTUnwrap(
      URL(
        string:
          "https://bruce.symphonious.net/auth/?error=access_denied&error_description=Not%20approved&state=expected"
      )
    )

    XCTAssertThrowsError(
      try client.authorizationCode(from: rejected, expectedState: "expected")
    ) { error in
      XCTAssertEqual(
        error as? HomeAssistantAuthenticationError,
        .authorizationRejected("Not approved")
      )
    }

    let missingCode = try XCTUnwrap(
      URL(string: "https://bruce.symphonious.net/auth/?state=expected")
    )
    XCTAssertThrowsError(
      try client.authorizationCode(from: missingCode, expectedState: "expected")
    ) { error in
      XCTAssertEqual(error as? HomeAssistantAuthenticationError, .missingAuthorizationCode)
    }
  }

  func testCallbackRejectsDuplicateAndConflictingOutcomeParameters() throws {
    let client = HomeAssistantAuthenticationClient()
    let ambiguousCallbacks = [
      "https://bruce.symphonious.net/auth/?code=one&code=two&state=expected",
      "https://bruce.symphonious.net/auth/?code=one&state=expected&state=expected",
      "https://bruce.symphonious.net/auth/?code=one&error=denied&state=expected",
      "https://bruce.symphonious.net/auth/?error=denied&error=other&state=expected",
    ]

    for callbackString in ambiguousCallbacks {
      let callback = try XCTUnwrap(URL(string: callbackString))
      XCTAssertThrowsError(
        try client.authorizationCode(from: callback, expectedState: "expected")
      ) { error in
        XCTAssertEqual(error as? HomeAssistantAuthenticationError, .invalidCallback)
      }
    }
  }

  func testCodeExchangeFormAndExpiry() async throws {
    let loader = RecordingAuthenticationLoader(
      data: Data(
        """
        {
          "access_token": "access-value",
          "refresh_token": "refresh-value",
          "token_type": "Bearer",
          "expires_in": 1800
        }
        """.utf8
      ),
      statusCode: 200
    )
    let now = Date(timeIntervalSince1970: 1_000)
    let client = HomeAssistantAuthenticationClient(loader: loader, now: { now })

    let token = try await client.exchangeCode(
      "code value",
      at: try XCTUnwrap(URL(string: "https://home.example.com"))
    )

    XCTAssertEqual(token.accessToken, "access-value")
    XCTAssertEqual(token.refreshToken, "refresh-value")
    XCTAssertEqual(token.expiresAt, Date(timeIntervalSince1970: 2_800))
    let request = try XCTUnwrap(loader.requests.first)
    XCTAssertEqual(request.url?.path, "/auth/token")
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(
      request.value(forHTTPHeaderField: "Content-Type"),
      "application/x-www-form-urlencoded"
    )
    XCTAssertEqual(
      String(data: try XCTUnwrap(request.httpBody), encoding: .utf8),
      "grant_type=authorization_code&code=code+value&client_id=https://bruce.symphonious.net/"
    )
  }

  func testRefreshAndRevokeUseExactForms() async throws {
    let loader = RecordingAuthenticationLoader(
      responses: [
        (
          Data(
            """
            {
              "access_token": "new-access",
              "token_type": "Bearer",
              "expires_in": 300
            }
            """.utf8
          ),
          200
        ),
        (Data(), 200),
      ]
    )
    let client = HomeAssistantAuthenticationClient(loader: loader)
    let baseURL = try XCTUnwrap(URL(string: "https://home.example.com"))

    _ = try await client.refresh(refreshToken: "refresh value", at: baseURL)
    try await client.revoke(refreshToken: "refresh value", at: baseURL)

    XCTAssertEqual(loader.requests.count, 2)
    XCTAssertEqual(
      String(data: try XCTUnwrap(loader.requests[0].httpBody), encoding: .utf8),
      "grant_type=refresh_token&refresh_token=refresh+value&client_id=https://bruce.symphonious.net/"
    )
    XCTAssertEqual(
      String(data: try XCTUnwrap(loader.requests[1].httpBody), encoding: .utf8),
      "action=revoke&token=refresh+value"
    )
  }

  func testServerAndMalformedResponsesAreTypedWithoutRequestSecrets() async throws {
    let rejectedLoader = RecordingAuthenticationLoader(
      data: Data(
        """
        {"error": "invalid_grant", "error_description": "Code is no longer valid"}
        """.utf8
      ),
      statusCode: 400
    )
    let rejectedClient = HomeAssistantAuthenticationClient(loader: rejectedLoader)
    let baseURL = try XCTUnwrap(URL(string: "https://home.example.com"))

    do {
      _ = try await rejectedClient.exchangeCode("secret-code", at: baseURL)
      XCTFail("Expected the server rejection.")
    } catch {
      XCTAssertEqual(
        error as? HomeAssistantAuthenticationError,
        .serverRejectedRequest(statusCode: 400, description: "Code is no longer valid")
      )
      XCTAssertFalse(String(describing: error).contains("secret-code"))
    }

    let malformedClient = HomeAssistantAuthenticationClient(
      loader: RecordingAuthenticationLoader(data: Data("{}".utf8), statusCode: 200)
    )
    do {
      _ = try await malformedClient.exchangeCode("code", at: baseURL)
      XCTFail("Expected an invalid token response.")
    } catch {
      XCTAssertEqual(error as? HomeAssistantAuthenticationError, .invalidTokenResponse)
    }
  }

  func testCancellationFromLoaderIsPreserved() async throws {
    let client = HomeAssistantAuthenticationClient(
      loader: RecordingAuthenticationLoader(error: CancellationError())
    )

    do {
      _ = try await client.exchangeCode(
        "code",
        at: try XCTUnwrap(URL(string: "https://home.example.com"))
      )
      XCTFail("Expected cancellation.")
    } catch {
      XCTAssertTrue(error is CancellationError)
    }
  }
}

private final class RecordingAuthenticationLoader: HomeAssistantHTTPDataLoading, @unchecked Sendable
{
  private let lock = NSLock()
  private var storedRequests: [URLRequest] = []
  private var responses: [(Data, Int)]
  private let error: (any Error)?

  var requests: [URLRequest] {
    lock.withLock { storedRequests }
  }

  init(data: Data, statusCode: Int) {
    responses = [(data, statusCode)]
    error = nil
  }

  init(responses: [(Data, Int)]) {
    self.responses = responses
    error = nil
  }

  init(error: any Error) {
    responses = []
    self.error = error
  }

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    if let error {
      throw error
    }
    let response = lock.withLock { () -> (Data, Int) in
      storedRequests.append(request)
      return responses.removeFirst()
    }
    let url = request.url ?? URL(fileURLWithPath: "/")
    guard
      let httpResponse = HTTPURLResponse(
        url: url,
        statusCode: response.1,
        httpVersion: nil,
        headerFields: nil
      )
    else {
      throw HomeAssistantAuthenticationError.unexpectedResponse
    }
    return (response.0, httpResponse)
  }
}
