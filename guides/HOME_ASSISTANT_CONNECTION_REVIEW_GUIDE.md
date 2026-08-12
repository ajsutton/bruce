# Home Assistant Connection Review Guide

**Platforms:** macOS 26+ and iOS 26+
**Status:** Mandatory for Home Assistant authentication, networking, live-update, and connection
lifecycle changes
**Required reviewer:** `home-assistant-connection-review`
**Research reviewed:** August 13, 2026

## Purpose

Bruce must maintain a coherent live Home Assistant session for as long as the product has an
active need for live data. Sleep and wake, interface changes, VPN changes, server restarts, router
restarts, idle connection expiry, token expiry, and transient transport failures are all ordinary
inputs to one connection lifecycle. None is a special reconnection architecture.

This guide defines the design and review standard. A change fails review if it adds another event-
specific recovery path without preserving the invariants below, even when its immediate regression
test passes.

The reviewer reports blocking findings when a Home Assistant connection-lifecycle change preserves
or adds competing lifecycle ownership, event-specific recovery, or another violation of this
guide. Fix the lifecycle as a coherent vertical slice; do not accept a wake-only, path-only,
settings-only, or feature-only patch because it improves one trigger. An unrelated presentation or
decoding change that does not alter connection behavior is outside this guide's migration gate.

The capitalized terms MUST, MUST NOT, SHOULD, and MAY describe Bruce repository requirements, not
requirements quoted from the linked standards.

## Core model

### Durable intent, replaceable transport

The supervisor and its focused dependencies MUST represent these separately:

- **Consumer intent:** whether active product consumers require live Home Assistant data.
- **Runnable transport intent:** consumer intent combined with ready credentials and an app state
  in which live updates should run.
- **Transport instance:** the current WebSocket attempt, which is disposable and identified by a
  generation.
- **Subscription intent:** the logical Home Assistant subscriptions consumers still require,
  independent of any one socket.
- **Presented freshness:** whether the last-known values are live, synchronizing, reconnecting,
  stale, unavailable, or require user action.

If runnable transport intent remains true, loss of a transport MUST start or continue recovery
without a user action. A transport error MUST NOT destroy consumer intent, subscription intent, or
the ability of current consumers to receive replacement data.

Consumer intent ends only when one of these is true:

- the user explicitly disconnects;
- no active product consumer requires live updates, according to the app's documented activity
  policy; or
- the owning app process terminates.

Runnable transport intent additionally requires ready credentials. Missing or definitively
rejected credentials suspend transport work and may leave consumer intent waiting for credentials;
they do not pretend that a transport can connect.

Sleep, wake, loss of network, a failed heartbeat, a server restart, a route change, and one failed
manual connection check MUST NOT end consumer intent.

### One connection control plane

One actor or equivalently serialized `HomeAssistantConnectionSupervisor` MUST own the complete
connection control plane:

- consumer and runnable transport intent;
- the authoritative connection state;
- the current attempt, transport, and lifecycle generation;
- route selection for the attempt;
- reconnect scheduling, jitter, and connectivity acceleration;
- heartbeat and liveness decisions;
- when authentication refresh is required for a connection attempt;
- logical subscription intent and resubscription;
- snapshot/event synchronization and the transition to live; and
- shutdown after explicit disconnect or loss of runnable intent.

Focused dependencies SHOULD remain separate: a credential session may atomically load, refresh,
persist, and revoke tokens; a connector may create a WebSocket; a passive broadcaster may fan out
the supervisor's updates; feature stores may transform those updates for presentation. These are
data-plane or service boundaries. They MUST NOT decide whether to reconnect, replace the shared
feed, rebuild observers, or declare the connection live.

Feature stores, setup UI, app-delegate notifications, path monitors, and manual checks send typed
events or intent changes to the supervisor. They do not perform recovery themselves. The
supervisor serializes those inputs and coalesces them into at most one attempt.

There MUST be at most one current connection attempt and one live Home Assistant WebSocket for an
authentication-session epoch. Use distinct identities for distinct invalidation domains:

- an authentication-session epoch changes on login, server replacement, or disconnect and
  invalidates the old socket and its publications;
- an access-token or credential-persistence generation prevents a stale refresh or route write
  from overwriting newer credentials, but an ordinary token refresh does not invalidate a healthy
  authenticated socket; and
- transport-attempt and lifecycle generations prevent replaced connection work from publishing,
  clearing ownership, or changing state.

Cancellation alone is insufficient protection. Every result MUST validate the identities relevant
to its own invalidation domain before publishing or persisting anything.

### Required migration from the current design

Bruce's current lifecycle is split between `HomeAssistantStateStream`, `HomeAssistantStateHub`,
`HomeAssistantObservationCoordinator`, setup callbacks, and app lifecycle callbacks. A terminal
stream can discard hub consumers, while outer layers try to reconstruct observation in response to
particular events. That architecture does not satisfy this guide.

The next implementation that changes any supervisor-owned control-plane concern listed above MUST
replace that split control plane with the supervisor architecture. This includes connection state,
transport, retry, heartbeat, route selection, connection authentication, subscriptions,
synchronization, and live readiness. The migration may retain useful protocol, token, ordering,
buffering, and feature transformation code behind narrower interfaces, but MUST remove independent
reconnect/refresh decisions from the retained types. Adding another callback between existing
owners is not an acceptable migration.

### Required state machine

The supervisor MAY use different names, but the following states and distinctions must be
represented by its authoritative state machine:

| State | Meaning | Permitted exit |
| --- | --- | --- |
| `stopped` | No consumer intent | Consumer intent becomes active or explicit connect supplies it |
| `waitingForCredentials` | Consumer intent exists but runnable credentials are absent | Credentials installed or consumer intent removed |
| `suspended` | Consumer intent and credentials exist, but app activity policy currently forbids live transport | App-policy resume, credentials replaced, or consumer intent removed |
| `connecting` | A new transport is being established | Authenticate, back off, require user action, or stop |
| `authenticating` | Waiting for Home Assistant `auth_required` / `auth_ok` | Synchronize, refresh once, back off, require user action, or stop |
| `synchronizing` | Subscriptions and a current snapshot are being established | Live, back off, require user action, or stop |
| `live` | Current transport is authenticated, subscribed, and synchronized | Back off, require user action, or stop |
| `backingOff` | Transient failure; retry is scheduled | Connect early on a useful signal, retry deadline, require user action, or stop |
| `waitingForConnectivity` | The system is waiting for a usable path | Connect when the task/path becomes viable, require user action, or stop |
| `requiresUserAction` | Recovery cannot proceed with current trust/configuration/credentials | Credentials or configuration replaced, or stop |

“Socket open” is not `live`. Bruce is live only after WebSocket authentication succeeds, required
subscriptions are acknowledged, a current state snapshot is reconciled, and the attempt is still
current.

## Continuous recovery

### Failure classification

The supervisor MUST classify errors by recovery action rather than by where they happened.

Retry indefinitely while runnable transport intent remains true for:

- dropped TCP/TLS/WebSocket connections;
- clean or abnormal server closure not requested by Bruce;
- DNS, offline, timeout, connection-lost, and connection-refused failures;
- heartbeat failure or a silent half-open connection;
- Home Assistant restart or temporary unavailability;
- transient OAuth token-endpoint failures;
- same-authentication-session staleness caused by a route or access-token update, after reevaluating
  current state rather than retrying obsolete work; and
- protocol or decoding failure after the connection has previously reached live, because a
  transient or rolling server change may recover.

Stop automatic retry and require user action only for a demonstrated terminal condition, such as:

- refresh-token rejection or an inactive/revoked Home Assistant user;
- missing credentials;
- a TLS trust decision that requires the user to change configuration or approve trust; or
- a deterministic initial authentication, subscription, or snapshot protocol failure before the
  connection has ever reached live, which indicates a wrong or incompatible endpoint.

Staleness caused by a replacement login, server, or authentication-session epoch MUST terminate
the obsolete attempt. The supervisor reevaluates current consumer and access intent and starts only
current-generation work; obsolete work never retries itself.

Never infer terminal authentication failure from a transport failure while refreshing a token.
Never delete credentials merely because the token endpoint was unreachable.

### Backoff and useful signals

Abnormal WebSocket closure MUST use randomized, increasing, capped backoff. This prevents a fleet
of clients from creating a reconnect storm, as required by the WebSocket protocol's recovery
guidance.

The default policy MUST use full jitter over an exponentially increasing window, beginning
within `0...5 seconds` and capped at no more than `60 seconds` while a foreground/live consumer is
active. The exact policy MUST be injectable so tests do not sleep.

Backoff MUST:

- continue at the cap rather than exhausting a finite retry list;
- coalesce multiple recovery signals into one attempt;
- preserve the failure count across attempts that open a socket but fail before becoming stably
  live;
- reset only after the connection is authenticated, subscribed, synchronized, and has remained
  healthy according to the documented policy; and
- be cancellable immediately when runnable transport intent ends or credentials are replaced.

A wake notification, app activation, network-path change, manual reconnect request, or new consumer
MAY accelerate the next attempt or request an immediate health check. Such a signal MUST enter the
supervisor's state machine, invalidate or coalesce the existing schedule safely, and MUST NOT create
a second recovery path.

### Connectivity APIs

Use the network operation itself as the authority on whether Home Assistant is reachable.

- Configure the shared `URLSession` to wait for connectivity when establishing requests rather
  than failing and polling while offline.
- Do not preflight requests with `SCNetworkReachability` or treat `NWPathMonitor` as proof that a
  specific Home Assistant endpoint is reachable.
- `NWPathMonitor` MAY accelerate a pending retry when the system path changes. It MUST remain a
  hint, not a gate, success condition, or second reconnect owner.
- A failed connection object is finished. Recovery creates a new transport owned by the same
  supervisor; it does not wait for callbacks from a failed object.
- Internal and external Home Assistant URLs are route candidates within one attempt policy. A
  route failure MUST not create parallel long-lived sockets.

Apple explicitly recommends `waitsForConnectivity` or a Network-framework connection's waiting
state instead of reachability preflight and manual polling. `waitsForConnectivity` only helps with
establishment; a connection that drops still reports an error, which the supervisor must recover.

### Liveness without waste

An open WebSocket can be half-open after sleep, NAT expiry, a router change, or a peer failure.
Bruce MUST combine continuous receiving with a bounded heartbeat deadline.

For Home Assistant, use its application-level `ping` command and correlated `pong`, because it
verifies the Home Assistant command path rather than only the WebSocket framing peer. The official
Home Assistant Swift library provides a useful energy baseline: a 60-second ping interval, a
30-second timeout, and timer tolerance.

Bruce MUST:

- treat any valid inbound Home Assistant message as liveness and postpone an otherwise unnecessary
  heartbeat until the connection has been idle for the heartbeat interval;
- use a default idle interval of about 60 seconds and a response deadline of no more than 30
  seconds, unless measurements justify different values;
- allow timer tolerance of at least 10 percent so macOS can coalesce wakeups;
- run only one heartbeat deadline for the current transport;
- cancel the transport and enter normal recovery after a missed heartbeat;
- treat a heartbeat timer that fires very late after sleep or App Nap as evidence that the old
  socket is suspect, then validate or replace it through the supervisor; and
- stop heartbeat work when runnable transport intent is false.

Do not add high-frequency pings, polling, separate wake timers, or repeated REST connection tests.
Measure with Xcode's Energy tools or Activity Monitor before shortening heartbeat or retry
intervals.

## Home Assistant protocol lifecycle

Each transport attempt MUST follow the Home Assistant WebSocket protocol:

1. Connect to `/api/websocket` using `ws` for HTTP or `wss` for HTTPS.
2. Receive `auth_required`.
3. Send the current access token in `auth` within Home Assistant's authentication window.
4. Receive `auth_ok`; handle `auth_invalid` through the token policy below.
5. Register every current logical subscription and verify each result.
6. Obtain and reconcile a current snapshot without losing events that arrive during the snapshot
   window.
7. Publish `live` only when the complete attempt is current and synchronized.
8. Continue receiving until cancellation or failure; never leave the socket without an active
   receive operation merely because no feature event is expected.

After reconnect, subscription command identifiers belong to the new socket. The supervisor MUST
re-register logical subscriptions and MUST NOT reuse transport-scoped identifiers as if they
survived.

The public live-data contract MUST survive transient reconnection. It may emit a reconnecting/stale
transition but MUST NOT finish and discard its consumers for a recoverable failure. An internal
transport attempt may finish; the supervisor replaces it while preserving subscriptions and
consumers.

## OAuth and credential lifecycle

### Authorization

Use Home Assistant's authorization-code flow through `ASWebAuthenticationSession`, with a random
and single-use `state` value bound to the pending attempt. Do not use an embedded web view or a
long-lived access token as a substitute for the native OAuth flow.

Home Assistant derives native client identity from the application's HTTPS client ID and approved
redirect URI. The authorization request and authorization-code exchange MUST use the matching
client ID, and refresh requests MUST send that same client ID. Home Assistant's `/auth/revoke`
endpoint requires the refresh token but does not require `client_id`.

PKCE SHOULD be used whenever the Home Assistant server supports it. Reviewers must distinguish
Home Assistant's actual server capability from the general OAuth native-app requirement and must
not add a client secret to a distributed app; a native app cannot keep one confidential.

### Refresh

Home Assistant access tokens are short lived; its documented response currently uses 1,800
seconds. The refresh token is the durable credential.

The session owner MUST:

- refresh shortly before expiry when a request or reconnect needs a token;
- coalesce concurrent WebSocket and REST refresh demand into one refresh operation;
- retain the existing refresh token when Home Assistant returns only a new access token;
- atomically persist a replacement refresh token if a future/server-specific response supplies
  one;
- use access-token or credential-persistence generations, or compare-and-swap semantics, so a late
  refresh cannot overwrite a
  newer login, server change, or disconnect;
- on REST `401` or WebSocket `auth_invalid`, force at most one refresh for the rejected access-token
  generation and retry with the resulting current token;
- treat token-endpoint network and server failures as transient without clearing credentials; and
- clear credentials and require authorization only when the refresh grant is definitively rejected
  or the user is inactive/revoked.

An access token expiring while an authenticated WebSocket is live does not by itself prove that the
socket is dead. Refresh before the next authenticated HTTP request or replacement WebSocket; do not
reconnect a healthy socket solely to rotate an access token unless Home Assistant requires it.

On explicit disconnect, cancel connection and refresh work, invalidate generations, revoke the
refresh token on a best-effort basis, and remove the local secret regardless of whether revocation
can reach the server.

### Secret handling

Store refresh and access tokens in Keychain Services. Tokens MUST NOT appear in logs, analytics,
errors, notification payloads, URLs, test fixtures committed with real values, or UI diagnostics.
Log credential and transport generations only as opaque locally generated identifiers.

## Data continuity and presentation

The last known value and its freshness are separate facts.

- On recoverable transport loss, preserve useful last-known values but mark them reconnecting or
  stale immediately.
- On explicit user disconnect, stop presenting values as reconnecting. Clear them or mark the
  feature signed out/unavailable according to its presentation contract.
- Do not present a successful REST `/api/` response, an open socket, or an `auth_ok` as proof that
  feature data is updating.
- Return to live only after replacement subscriptions and snapshot reconciliation succeed.
- A manual **Test Connection** action MUST exercise or await the supervisor's end-to-end live
  readiness. It MUST NOT display success for an independent probe while the shared feed is dead.
- Commands issued while reconnecting need an explicit policy: reject with an honest retryable
  state, or queue only operations proven safe and idempotent. Never silently lose or duplicate a
  control action.
- Reconnect must not roll back newer events with an older REST snapshot, resurrect removed
  entities, or apply messages from a superseded route, authentication session, or transport attempt.

## Energy contract

Continuous connection does not mean continuous work.

- Share one upstream Home Assistant feed across feature consumers.
- Open no transport when there is no documented active consumer.
- Prefer pushed state changes over polling.
- Reuse a shared `URLSession` so the system can pool and schedule networking efficiently.
- Keep retry and heartbeat timers bounded, cancellable, coalesced, and tolerant.
- Do not prevent App Nap merely to preserve a socket. Assume timers may be throttled and validate
  liveness when execution resumes.
- Avoid reloading unchanged registries or full history after every reconnect. Reload only data
  whose freshness cannot be reconstructed from the replacement snapshot and buffered events.
- Do not use background `URLSession` as a WebSocket keepalive mechanism; background transfer
  sessions are for deferrable HTTP uploads and downloads.

Any change that adds a timer, path monitor, wake observer, periodic request, or additional socket
MUST explain its owner, cancellation point, coalescing behavior, and measured energy need.

## Observability

Connection diagnostics SHOULD record structured, privacy-safe transitions containing:

- previous and next lifecycle state;
- trigger category, such as transport close, heartbeat, path hint, wake hint, manual request, or
  authentication result;
- transport, credential, and lifecycle generation identifiers;
- route category without sensitive URL components;
- retry attempt, chosen jittered delay, and whether a useful signal accelerated it;
- time to connect, authenticate, subscribe, synchronize, and become live; and
- last successful event time and terminal/nonterminal error classification.

Logs MUST make it possible to distinguish “REST probe succeeded” from “shared live feed became
live.” Never log tokens, authorization codes, full URLs containing user information, entity state
payloads, or refresh request bodies.

## Required deterministic tests

Connection-lifecycle changes MUST inject every affected nondeterministic boundary. Depending on the
behavior, these may include clocks, retry policies, connectors, credential stores, and event
streams. Tests MUST not sleep or depend on an actual network.

At minimum, cover the affected rows of this matrix and preserve broad integration coverage for the
whole lifecycle:

| Scenario | Required assertion |
| --- | --- |
| TCP/WebSocket EOF or network-lost error | One replacement attempt starts and current consumers remain registered |
| Clean server close | It reconnects unless Bruce requested the close |
| Silent half-open socket | Heartbeat deadline cancels it and starts normal recovery |
| Home Assistant restart | Authentication, subscriptions, snapshot, and fresh events recover automatically |
| Network absent at attempt start | The operation waits/backoffs without polling or exhausting recovery |
| Path change during backoff | At most one attempt is accelerated; no parallel socket starts |
| Sleep/App Nap makes heartbeat fire late | Old transport is validated/replaced through the supervisor |
| Wake while retry or connect is active | Work is coalesced; the older generation cannot publish |
| Repeated failures | Backoff reaches its cap and continues until success or intent ends |
| Explicit disconnect/no consumers | Retry, heartbeat, receive, refresh, and path work stop |
| App activity suspends and resumes | Transport work stops without losing consumer/subscription intent, then one current attempt resumes automatically |
| Access token near expiry | One coalesced refresh supplies REST and WebSocket callers |
| `auth_invalid`, refresh succeeds | Exactly one forced refresh occurs and replacement authentication uses the new token |
| Refresh endpoint is offline | Credentials remain stored and automatic recovery continues |
| Refresh grant is rejected | Connection stops, credentials clear coherently, and UI requires authorization |
| Login/server changes during refresh | The stale refresh cannot persist or publish |
| Preferred route fails | The alternate route is tried without parallel long-lived connections |
| Reconnect completes | All logical subscriptions are registered on the new socket |
| Events arrive during snapshot load | Reconciliation publishes the newest state and preserves removals |
| Recoverable transport fails | The public feed emits stale/reconnecting but does not strand or finish consumers |
| Manual Test Connection succeeds | Shared feature data reaches a new live value before success is shown |
| Manual Test Connection fails | The probe error is honest, but ready access, current values, and shared-feed recovery intent remain intact |
| Reconnect attempt is cancelled/replaced | No task/owner retain cycle and no stale status or data publication |
| Registry event after reconnect | Dependent metadata invalidates and reloads exactly once for the new generation; old metadata is not presented as newly live |

Every concurrency test MUST bound its waits and clean up blocked test work even on assertion
failure. Assert attempt, socket, subscription, refresh, snapshot, and history-request counts where
duplicate work would be user-visible or waste energy.

## Review rejection patterns

Report a finding when a change introduces or preserves any of these patterns:

- wake, activation, path, or settings callbacks directly rebuild feature observations;
- a finite retry list ends a recoverable live feed;
- a transient source failure finishes the shared public stream and discards subscribers;
- each feature store owns its own socket or reconnect loop;
- `NWPathMonitor` decides that Home Assistant is reachable or blocks an otherwise valid attempt;
- connection success is derived from an independent REST probe;
- socket-open or authentication success is presented as live before subscriptions and data recover;
- heartbeat, retry, wake, and manual refresh can overlap as separate tasks;
- a task can publish after its relevant authentication-session, transport-attempt, or lifecycle
  identity is superseded, or a stale credential/route operation can persist after its own
  persistence generation is superseded;
- refresh-token network failure is treated as revocation;
- an access token is refreshed concurrently by multiple callers;
- retry timers poll rapidly while offline or heartbeat timers continue without consumers;
- resubscription relies on feature views disappearing and reappearing; or
- a regression test proves only a callback fired, not that replacement Home Assistant data became
  live for an existing consumer.

## Reviewer checklist

Before approving, answer all of these from the changed code and tests:

- What represents consumer intent and runnable transport intent, and what may turn each off?
- Does one supervisor own every connection state transition and replace every failed transport?
- Can any recoverable error finish the consumer contract or lose subscription intent?
- Can wake, path, heartbeat, retry, manual action, and token refresh start overlapping attempts?
- Which authentication-session, credential-persistence, transport-attempt, and lifecycle identities
  protect their distinct invalidation domains without needlessly replacing a healthy socket?
- Does recovery continue indefinitely with jittered capped backoff?
- What exact condition moves presentation to live?
- Are subscriptions and the current snapshot restored without an event gap or rollback?
- Does token rejection get one coalesced refresh, while token-network failure preserves credentials?
- Does **Test Connection** prove the shared feed and displayed data recovered?
- What stops the transport, receive, heartbeat, retry, and path work whenever runnable transport
  intent is false, including suspension, missing/rejected credentials, disconnect, and no consumers?
- Do tests prove replacement data reaches every affected presentation path?
- Do logs diagnose the lifecycle without exposing secrets or household state?

If any answer is unclear, ownership is unclear and the change is not ready.

## Research basis

The design above combines platform and protocol requirements with patterns used by Home
Assistant's maintained clients:

- [Home Assistant WebSocket API](https://developers.home-assistant.io/docs/api/websocket/) defines
  the authentication state sequence, command correlation, subscriptions, and application
  `ping`/`pong` heartbeat.
- [Home Assistant Authentication API](https://developers.home-assistant.io/docs/auth_api/) defines
  native client identity, authorization-code exchange, 1,800-second access tokens, refresh,
  revocation, and the distinction between `401`, invalid refresh, and inactive-user responses.
- [Home Assistant JavaScript connection implementation](https://github.com/home-assistant/home-assistant-js-websocket/blob/master/lib/connection.ts)
  keeps logical subscriptions across socket replacement and reconnects until explicitly closed or
  authentication is invalid.
- [Home Assistant JavaScript socket authentication](https://github.com/home-assistant/home-assistant-js-websocket/blob/master/lib/socket.ts)
  refreshes an expired access token before WebSocket authentication and treats invalid
  authentication differently from inability to connect.
- [Home Assistant HAKit](https://github.com/home-assistant/HAKit) documents that a requested
  connection keeps reconnecting on network changes and retry deadlines, and that subscriptions
  automatically re-register.
- [HAKit reconnect manager](https://github.com/home-assistant/HAKit/blob/main/Source/Internal/HAReconnectManager.swift)
  provides the Home Assistant Swift client's heartbeat, timeout, late-timer, path-change, and
  indefinite reconnect with capped-delay precedent.
- [Apple: Adapt to changing network conditions](https://developer.apple.com/videos/play/tech-talks/111378/)
  recommends connection waiting and `waitsForConnectivity` instead of reachability preflight and
  manual polling.
- [Apple: `waitsForConnectivity`](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/waitsforconnectivity)
  clarifies that waiting applies to establishment and dropped established connections still
  report errors.
- [Apple: `URLSessionWebSocketTask`](https://developer.apple.com/documentation/foundation/urlsessionwebsockettask)
  defines the system WebSocket transport and one-message receive operation.
- [Apple: Reducing networking power usage](https://developer.apple.com/documentation/xcode/reducing-networking-and-bluetooth-power-usage)
  recommends shared system networking APIs, connection reuse, batching, and waiting for viable
  connectivity.
- [Apple: Minimize timer usage](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/Timers.html)
  recommends event-driven work, cancelling unused timers, meaningful timeouts, and timer tolerance.
- [Apple: App Nap](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/AppNap.html)
  explains timer and I/O throttling and why an inactive app should approach idle proactively.
- [Apple: `ASWebAuthenticationSession`](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession)
  provides the secure system-browser OAuth flow on macOS and protects callback delivery.
- [Apple Keychain Services](https://developer.apple.com/documentation/security/keychain-services)
  is the platform facility for encrypted storage of small secrets.
- [RFC 6455 section 7.2.3](https://www.rfc-editor.org/rfc/rfc6455.html#section-7.2.3)
  requires clients to avoid immediate persistent reconnect storms and recommends randomized,
  increasing backoff.
- [RFC 8252](https://www.rfc-editor.org/rfc/rfc8252.html) defines OAuth best current practice for
  native apps, including external user agents and PKCE.
- [RFC 9700](https://www.rfc-editor.org/rfc/rfc9700.html) defines current OAuth security practice,
  including refresh-token replay protections. Bruce can consume only protections supported by the
  user's Home Assistant server and MUST NOT invent an embedded client secret.
