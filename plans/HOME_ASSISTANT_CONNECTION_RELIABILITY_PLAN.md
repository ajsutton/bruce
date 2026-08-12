# Home Assistant Connection Reliability Plan

## Problem

Connection recovery is currently split across setup verification, the WebSocket state stream, the
shared state hub, feature observation, scene activity, the macOS application delegate, and manual
refresh. A transient network failure can therefore change credential/setup state, terminate the
shared feed, discard every subscriber, or require an unrelated lifecycle event to restart data.

The design also uses `HomeAssistantConnectionState` for two different facts:

- whether Bruce has usable Home Assistant credentials; and
- whether the server happens to be reachable now.

That ambiguity lets point-in-time checks control the lifetime of the continuous data connection.

## Ownership

The redesigned system has one owner for each concern.

### Access state

`HomeAssistantAccessState` describes only local authorization/configuration:

- signed out;
- loading saved access;
- ready; or
- requiring user action.

Transient connectivity never changes access state. Restoring saved credentials makes access ready
without waiting for a network probe. Authentication rejection may require user action.
The access state carries only stable server identity, not tokens or preferred-route data, so token
refreshes, route changes, and manual verification cannot masquerade as an observation-lifecycle
change.

### Live connection

`HomeAssistantStateStream` owns all transport recovery. Its stream has this contract:

- connectivity and server availability failures retry forever with bounded backoff;
- retry covers initial token/access preparation, WebSocket establishment, authentication,
  subscription, REST snapshot loading, and later receives;
- a transport heartbeat turns half-open sockets into ordinary retryable failures;
- reconnecting is published before waiting;
- cancellation stops the current connection and retry delay;
- only missing/rejected credentials or an unrecoverable protocol/configuration error terminate the
  stream.

No caller retries the state stream.

### Fan-out

`HomeAssistantStateHub` only shares the single continuous state stream and preserves the newest
snapshot across refresh/reconnect transitions. It does not decide whether an error is recoverable.

### Presentation and lifecycle

`HomeAssistantObservationCoordinator` starts observation when access is ready and stops it when
access is removed, requires user action, or the app intentionally suspends updates. Server status
is derived from live stream updates, not setup verification.

Manual connection tests report their own result but do not revoke ready access or restart live
observation after transient failures. Platform lifecycle code expresses activity only; it does not
repair connection state.

## Invariants

1. A transient network error cannot change ready access to signed out or requiring user action.
2. While access is ready and observation is active, exactly one shared source owns reconnect.
3. Every recoverable source failure leads to another attempt unless the owner is cancelled.
4. Backoff is bounded and cancellation-aware.
5. Old attempts cannot publish after access, activity, or source generation changes.
6. A manual connection check cannot start, stop, or replace live observation because of a
   transient error.
7. Authentication rejection terminates old observation and requires explicit reauthentication.
8. Cached values remain visible but non-live while reconnecting or refreshing.

## Verification

Deterministic tests must cover:

- a connectivity failure before the first WebSocket access is prepared;
- connection loss after live data followed by recovery;
- repeated failure at the maximum backoff;
- route replacement and token refresh while reconnecting;
- cancellation during connection, receive, and retry delay;
- restoring credentials while offline without gating data-plane startup;
- a failed manual connection test leaving live observation attached;
- authentication rejection stopping the old access generation; and
- heartbeat failure replacing a half-open source without relying on system wake.
