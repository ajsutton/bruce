import Foundation

struct HomeAssistantAuthenticatedResponse: Sendable {
  let data: Data
  let baseURL: URL
}

actor HomeAssistantAuthenticatedTransport {
  private let loader: any HomeAssistantHTTPDataLoading
  private var requestTasks: [UUID: Task<(Data, HTTPURLResponse), any Error>] = [:]

  init(loader: any HomeAssistantHTTPDataLoading) {
    self.loader = loader
  }

  func get(
    path: String,
    queryItems: [URLQueryItem] = [],
    credentials: HomeAssistantCredentials
  ) async throws -> HomeAssistantAuthenticatedResponse {
    try await request(
      path: path,
      queryItems: queryItems,
      credentials: credentials,
      allowsFallback: true
    )
  }

  func getFirstAvailable(
    path: String,
    credentials: HomeAssistantCredentials,
    validate: @escaping @Sendable (Data) throws -> Void
  ) async throws -> HomeAssistantAuthenticatedResponse {
    let candidates = try HomeAssistantRequestRouter.candidates(for: credentials)
    guard candidates.count > 1 else {
      let response = try await request(
        path: path,
        credentials: credentials,
        allowsFallback: true
      )
      try validate(response.data)
      return response
    }
    return try await withThrowingTaskGroup(
      of: RouteAttempt.self,
      returning: HomeAssistantAuthenticatedResponse.self
    ) { group in
      for (index, baseURL) in candidates.enumerated() {
        group.addTask {
          do {
            let response = try await self.response(
              baseURL: baseURL,
              path: path,
              credentials: credentials
            )
            try validate(response.data)
            return .success(response)
          } catch {
            return .failure(index, error)
          }
        }
      }

      var failures = [(any Error)?](repeating: nil, count: candidates.count)
      for try await attempt in group {
        switch attempt {
        case .success(let response):
          group.cancelAll()
          try Task.checkCancellation()
          return response
        case .failure(let index, let error):
          failures[index] = error
        }
      }
      try Task.checkCancellation()
      throw Self.preferredFailure(from: failures)
    }
  }

  func post(
    path: String,
    body: Data,
    credentials: HomeAssistantCredentials
  ) async throws -> HomeAssistantAuthenticatedResponse {
    try await request(
      path: path,
      method: "POST",
      body: body,
      credentials: credentials,
      allowsFallback: false
    )
  }

  private func request(
    path: String,
    queryItems: [URLQueryItem] = [],
    method: String = "GET",
    body: Data? = nil,
    credentials: HomeAssistantCredentials,
    allowsFallback: Bool
  ) async throws -> HomeAssistantAuthenticatedResponse {
    let candidates = try HomeAssistantRequestRouter.candidates(for: credentials)
    var lastConnectivityError: (any Error)?
    for (index, baseURL) in candidates.enumerated() {
      do {
        return try await response(
          baseURL: baseURL,
          path: path,
          queryItems: queryItems,
          method: method,
          body: body,
          credentials: credentials
        )
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        guard
          allowsFallback,
          HomeAssistantRequestRouter.isConnectivityFailure(error),
          index + 1 < candidates.count
        else {
          throw error
        }
        lastConnectivityError = error
      }
    }
    throw lastConnectivityError ?? HomeAssistantAPIError.invalidServerURL
  }

  private func response(
    baseURL: URL,
    path: String,
    queryItems: [URLQueryItem] = [],
    method: String = "GET",
    body: Data? = nil,
    credentials: HomeAssistantCredentials
  ) async throws -> HomeAssistantAuthenticatedResponse {
    let request = try HomeAssistantRequestRouter.authenticatedRequest(
      baseURL: baseURL,
      path: path,
      queryItems: queryItems,
      token: credentials.accessToken,
      method: method,
      body: body
    )
    let (data, response) = try await load(request)
    guard response.statusCode != 401 else {
      throw HomeAssistantAPIError.unauthorized
    }
    guard (200..<300).contains(response.statusCode) else {
      throw HomeAssistantAPIError.server(statusCode: response.statusCode)
    }
    try Task.checkCancellation()
    return HomeAssistantAuthenticatedResponse(data: data, baseURL: baseURL)
  }

  private static func preferredFailure(
    from failures: [(any Error)?]
  ) -> any Error {
    let errors = failures.compactMap(\.self)
    return errors.first(where: { !HomeAssistantRequestRouter.isConnectivityFailure($0) })
      ?? errors.last
      ?? HomeAssistantAPIError.invalidServerURL
  }

  func cancelAll() {
    requestTasks.values.forEach { $0.cancel() }
    requestTasks.removeAll()
  }

  private func load(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let identifier = UUID()
    let task = Task { [loader] in
      let result = try await loader.data(for: request)
      try Task.checkCancellation()
      return result
    }
    requestTasks[identifier] = task
    defer {
      requestTasks[identifier] = nil
    }
    return try await withTaskCancellationHandler {
      let result = try await task.value
      try Task.checkCancellation()
      return result
    } onCancel: {
      task.cancel()
    }
  }
}

private enum RouteAttempt: Sendable {
  case success(HomeAssistantAuthenticatedResponse)
  case failure(Int, any Error)
}
