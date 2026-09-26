import Foundation

/// Uses the app’s authenticated session and fetches server state for every invocation.
struct BruceSiriService: Sendable {
  let energy: any HomeAssistantHomeEnergyLoading
  let charger: any HomeAssistantEVCharging
  let prepare: @Sendable () async throws -> Void
  var waitForTimeout: @Sendable () async throws -> Void = {
    try await Task.sleep(for: .seconds(12))
  }

  func solarGeneration() async throws -> Double {
    try await reading { $0.pvPowerKilowatts }
  }

  func batteryLevel() async throws -> Double {
    try await reading { $0.batteryStateOfCharge }
  }

  func electricityUsage() async throws -> Double {
    try await reading { $0.homeConsumptionKilowatts }
  }

  func chargerMode() async throws -> HomeAssistantEVChargingMode {
    try await request { try await charger.loadEVChargingMode() }
  }

  func chargerStatus() async throws -> HomeAssistantEVChargingActivity {
    try await request {
      let snapshot = try await charger.loadEVChargingSnapshot()
      guard snapshot.activity != .unavailable else { throw BruceSiriError.unavailable }
      return snapshot.activity
    }
  }

  func setChargerMode(_ mode: HomeAssistantEVChargingMode) async throws {
    do {
      try await request {
        // A service acknowledgement alone does not prove the requested mode was applied.
        let confirmed = try await charger.setEVChargingMode(mode)
        guard confirmed == mode else { throw BruceSiriError.modeNotConfirmed }
      }
    } catch is CancellationError {
      throw CancellationError()
    } catch BruceSiriError.signInRequired {
      throw BruceSiriError.signInRequired
    } catch {
      // A timeout or lost response may occur after the server has applied the mode.
      throw BruceSiriError.modeNotConfirmed
    }
  }

  private func reading(
    _ value: @escaping @Sendable (HomeAssistantHomeEnergySnapshot) -> Double?
  ) async throws -> Double {
    try await request {
      let snapshot = try await energy.loadHomeEnergySnapshot()
      guard let reading = value(snapshot), reading.isFinite else {
        throw BruceSiriError.unavailable
      }
      return reading
    }
  }

  private func request<Value: Sendable>(
    _ operation: @escaping @Sendable () async throws -> Value
  ) async throws -> Value {
    do {
      return try await BruceSiriRequest.run(waitForTimeout: waitForTimeout) {
        try await prepare()
        try Task.checkCancellation()
        let result = try await operation()
        try Task.checkCancellation()
        return result
      }
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as BruceSiriError {
      throw error
    } catch HomeAssistantAPIError.invalidResponse {
      throw BruceSiriError.unavailable
    } catch HomeAssistantAPIError.noCredentials {
      throw BruceSiriError.signInRequired
    } catch HomeAssistantAPIError.unauthorized {
      throw BruceSiriError.signInRequired
    } catch HomeAssistantAPIError.reauthenticationRequired {
      throw BruceSiriError.signInRequired
    } catch {
      throw BruceSiriError.connectionUnavailable
    }
  }
}
