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
    credentials: HomeAssistantCredentials
  ) async throws -> HomeAssistantAuthenticatedResponse {
    try await request(path: path, credentials: credentials, allowsFallback: true)
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
    method: String = "GET",
    body: Data? = nil,
    credentials: HomeAssistantCredentials,
    allowsFallback: Bool
  ) async throws -> HomeAssistantAuthenticatedResponse {
    let candidates = try HomeAssistantRequestRouter.candidates(for: credentials)
    var lastConnectivityError: (any Error)?
    for (index, baseURL) in candidates.enumerated() {
      do {
        let request = try HomeAssistantRequestRouter.authenticatedRequest(
          baseURL: baseURL,
          path: path,
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
