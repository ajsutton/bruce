# Home Assistant Connection Plan

## Status

Proposed specification. No discovery, authentication, credential storage, or Home Assistant API
code is approved by this document alone.

## Goal

Let a household member connect Bruce to their Home Assistant instance without needing to know its
network address or create a long-lived access token manually.

The completed setup should:

- discover Home Assistant instances advertised on the local network;
- let the user confirm the correct home or enter an address manually;
- authenticate through Home Assistant's OAuth flow;
- retain the resulting credentials securely on the current device;
- provide an authenticated session that later features can use to fetch Home Assistant data; and
- present clear recovery paths when discovery, authentication, or connectivity fails.

The first expected data feature is room temperature. Connection work should enable that feature
without embedding temperature, room, or dashboard concepts in discovery or authentication types.

## Non-goals

This slice will not:

- build the room-temperature UI;
- infer rooms from entity names or Home Assistant friendly names;
- implement a generic entity browser or Home Assistant administration UI;
- add Home Assistant device registration, notifications, webhooks, or remote commands;
- sync credentials through iCloud or another service;
- accept or persist a user-created long-lived access token;
- bypass TLS validation or trust self-signed certificates silently; or
- depend on Home Assistant Cloud.

## Product flow

```text
Connection introduction
        |
        v
Local-network permission and discovery
        |
        +-- one or more instances --> user confirms an instance
        |
        +-- none / unavailable -----> manual address entry
                                      |
                                      v
                              validate server address
                                      |
                                      v
                         Home Assistant OAuth in system session
                                      |
                         +------------+-------------+
                         |                          |
                      success              cancel / error
                         |                          |
                         v                          v
                securely save session       actionable recovery
                         |
                         v
              authenticated connection check
                         |
                         v
                    setup complete
```

Discovery must reduce typing, not remove user control. Bruce must show the selected home and ask
the user to continue before opening its sign-in page. This prevents an unexpected or malicious
local advertisement from initiating authentication without confirmation.

## External protocol requirements

### Instance discovery

Home Assistant advertises `_home-assistant._tcp.local.` using mDNS/Zeroconf. Its TXT record may
contain:

- `uuid`: the stable Home Assistant instance identifier;
- `location_name`: the user-facing instance name;
- `version`: the Home Assistant Core version, when known;
- `internal_url`: the preferred LAN URL, when configured;
- `external_url`: the remote URL, when configured;
- `base_url`: a deprecated compatibility URL; and
- `landingpage`: a marker for an instance that has not completed Home Assistant onboarding.

Bruce must capture both `internal_url` and `external_url` when Home Assistant advertises them.
Discovery will normally happen on the same LAN as the internal URL, but retaining the external
URL lets the authenticated app continue working after the device leaves home.

If `internal_url` is absent, the discovery implementation should resolve the advertised service
host and port as an internal connection candidate. `base_url` should be used only as a
compatibility fallback and must not replace a distinct internal or external URL. The obsolete
`requires_api_password` property must be ignored.

### Authentication

Home Assistant uses OAuth 2 with IndieAuth-style client identification:

1. Bruce opens `<instance>/auth/authorize` with `client_id`, `redirect_uri`, and a cryptographically
   random `state`.
2. Home Assistant redirects to Bruce with an authorization `code` and the same `state`.
3. Bruce verifies `state`.
4. Bruce exchanges the code at `<instance>/auth/token` using an
   `application/x-www-form-urlencoded` request.
5. Home Assistant returns an access token, refresh token, token type, and access-token lifetime.
6. Bruce uses `Authorization: Bearer <access token>` for API requests.

The refresh token is exchanged at the same token endpoint when the access token expires. The
active internal or external instance URL determines which token endpoint is used. A disconnect
action should revoke the refresh token through an available instance URL before deleting the
local credentials.

### Transport security

Bruce will support Home Assistant's common local HTTP configuration with these limits:

- an `http://` URL may be used only as a confirmed internal connection candidate;
- a discovered `internal_url` or resolved mDNS service becomes confirmed only after the user
  selects that advertised Home Assistant instance;
- a manually entered HTTP URL is treated as an internal candidate only after Bruce warns that the
  connection is not encrypted and the user explicitly continues;
- an external connection candidate must use trusted HTTPS;
- an advertised HTTP `external_url` is retained as discovery metadata but is not eligible for
  authentication or API requests;
- Bruce must never follow a redirect that downgrades HTTPS to HTTP or forwards authorization to
  another origin; and
- support for local HTTP must not weaken TLS or App Transport Security globally.

This policy accepts the practical risk of sending credentials without TLS on a user-confirmed
local network while preventing the same behaviour over the Internet.

### OAuth client identity and callback

Bruce will use these permanent OAuth values:

```text
Client ID:    https://bruce.symphonious.net/
Redirect URI: https://bruce.symphonious.net/auth/
```

The client ID is the public website for the application. The root will become Bruce's marketing
site. The redirect URI uses the same HTTPS host and port, so Home Assistant permits it without a
custom-scheme redirect declaration.

The app should handle the redirect with an `ASWebAuthenticationSession` configured for the exact
HTTPS host `bruce.symphonious.net` and path `/auth/`. It must still validate the complete callback
URL and OAuth `state` before accepting an authorization code.

These URLs are part of Bruce's long-lived protocol identity:

- use the exact client ID, including its trailing slash, in authorization-code and refresh-token
  requests;
- do not vary either URL by build configuration;
- keep the domain and `/auth/` route available for existing app versions; and
- do not replace the HTTPS callback with a custom URL scheme unless a later security review
  requires it.

### Minimal GitHub Pages prerequisite

The initial website should be a deliberately small static GitHub Pages site. A separate design
task can replace the root content without changing the OAuth URLs.

The minimal source should contain:

```text
docs/
  .nojekyll
  CNAME
  index.html
  .well-known/
    apple-app-site-association
  auth/
    index.html
```

Requirements:

- `CNAME` contains only `bruce.symphonious.net`;
- `.well-known/apple-app-site-association` declares the Bruce application identifier under
  `webcredentials.apps`;
- the association file is served directly over HTTPS without a redirect and with a JSON-compatible
  content type;
- the root page identifies Bruce as an iPhone and Mac client for a Home Assistant-backed home and
  makes no claims about unimplemented features;
- `/auth/` is a benign fallback page explaining that authentication should return to Bruce;
- the auth page must not inspect, render, store, forward, or log authorization codes or `state`;
- both pages work without JavaScript, cookies, analytics, forms, or external assets;
- the Pages site is publicly reachable even while the application repository remains private;
- GitHub Pages serves from `main` and `/docs`;
- the `bruce.symphonious.net` DNS record points to the GitHub Pages host;
- the custom domain is verified for the `ajsutton` GitHub account to reduce domain-takeover risk;
  and
- GitHub Pages enforces HTTPS after its certificate is issued.

The root marketing page and `/auth/` fallback are support infrastructure only. Home Assistant
credentials and token exchange remain between Bruce and the user's Home Assistant instance; the
GitHub Pages site must never receive or proxy tokens.

Apple requires an HTTPS `ASWebAuthenticationSession` callback host to be associated with the app
using Associated Web Credentials. Both Apple-side declarations are required:

- the app entitlement contains `webcredentials:bruce.symphonious.net`; and
- the public association file contains `<Apple Team ID>.net.symphonious.bruce`.

If GitHub Pages cannot serve the association file in a form accepted by Apple, the callback host
must move to static hosting that can set the required response headers. Do not fall back to a
custom URL scheme merely to avoid validating the HTTPS association.

## Backend design

### 1. Discovered instance value

Add a `HomeAssistantInstance` value with:

- stable instance identifier;
- display name;
- internal URL, when advertised or resolved;
- external URL, when advertised;
- Home Assistant version, when advertised; and
- onboarding state.

It should be an immutable, `Sendable`, `Equatable` value. Discovery metadata must not contain
credentials.

The internal and external URLs are separate optional properties, not a single selected base URL.
The value should expose unique connection candidates without discarding either role. It must not
claim that a candidate is reachable until a connection check succeeds.

### 2. Discovery client

Add a focused discovery boundary backed by Network framework Bonjour browsing.

Responsibilities:

- browse `_home-assistant._tcp` in the `local.` domain;
- parse and validate Home Assistant TXT records;
- retain both valid `internal_url` and `external_url` values from each record;
- resolve host and port when no usable internal URL is advertised;
- deduplicate records by stable Home Assistant UUID;
- publish deterministic snapshots ordered by display name and UUID;
- update or remove instances as browse results change;
- surface browser failures and local-network permission failures;
- stop browsing and release handlers promptly when cancelled; and
- never retain a discovery task beyond its owning setup screen or store.

The consumer-facing API should provide an asynchronous stream of discovery snapshots. A stream
matches Bonjour's changing result set and gives the setup UI an honest searching state without
polling or arbitrary delays.

The Network framework adapter should sit behind a small substitution boundary so tests can feed
synthetic advertisements without opening sockets. The boundary is justified by operating-system
I/O and deterministic cancellation tests; it must not become a general networking framework.

### 3. Manual server validation

Manual entry is required even when discovery works.

Validation should:

- trim surrounding whitespace;
- require an `http` or `https` URL with a host;
- treat a manually entered HTTP URL as internal and require an explicit insecure-connection
  confirmation before authentication;
- reject embedded credentials and fragments;
- preserve an explicit port;
- normalize away API or authentication endpoint suffixes so the stored value represents the
  instance root;
- call the unauthenticated Home Assistant authorization entry point only through the OAuth
  session, rather than probing arbitrary endpoints for credentials; and
- report malformed address, DNS, transport, TLS, timeout, and non-Home-Assistant responses
  distinctly where recovery differs.

Bruce must never disable TLS checks. A Home Assistant instance using a private or self-signed
certificate needs an explicit future trust design; it is not silently accepted by this slice.

### 4. Authentication client

Add a `HomeAssistantAuthenticationClient` responsible for protocol construction and token
requests, not browser presentation or credential persistence.

Responsibilities:

- construct the authorization URL from the instance URL and release OAuth configuration;
- generate or accept a caller-generated high-entropy `state`;
- validate the callback scheme, host/path, state, authorization code, and OAuth error values;
- exchange an authorization code for credentials;
- refresh an access token;
- revoke a refresh token;
- form-encode request bodies correctly;
- decode successful token responses; and
- preserve useful Home Assistant error descriptions without exposing token values.

Authorization callbacks and token requests must never be logged in full because they contain
short-lived secrets.

### 5. Credential value and secure storage

Separate the wire responses from the persisted credential value.

The stored credential record should contain:

- instance identifier and display name;
- internal and external instance URLs when known;
- the most recently successful instance URL;
- access token;
- refresh token;
- token type;
- access-token expiry date;
- OAuth client ID needed for refresh; and
- a schema version for future migration.

Store credentials in Keychain with device-only accessibility appropriate for use after the user
unlocks the device. Do not place tokens in `UserDefaults`, ubiquitous key-value storage, logs,
analytics, previews, test fixtures checked into the repository, or iCloud-synchronizable Keychain
items.

Each Apple device authenticates independently. Non-secret presentation data such as the selected
instance name may be stored separately only when a UI feature needs it.

Credential storage needs a narrow protocol because Keychain is an external boundary and tests
must prove save, replace, load, and delete behaviour without changing the developer's Keychain.

### 6. Authenticated session

Add an actor-owned `HomeAssistantSession` after authentication and storage exist.

Responsibilities:

- own the current credential state;
- attach the bearer token to requests;
- select between the internal and external instance URLs without requiring the user to switch
  modes;
- try the most recently successful URL first, then the other known URL after a qualifying
  connectivity failure;
- remember a newly successful URL so subsequent requests do not repeatedly wait on an unreachable
  endpoint;
- refresh before expiry;
- coalesce concurrent refresh attempts into one operation;
- update Keychain only after a successful refresh;
- retry one request after a `401` only when refresh succeeds;
- distinguish cancellation, offline state, revoked credentials, server errors, and decoding
  errors;
- clear unusable local credentials when Home Assistant rejects the refresh token; and
- never allow an older refresh result to replace newer credentials.

Transport requests should remain cancellable through structured concurrency. Retrying must be
bounded; authentication failures must not create loops.

Automatic endpoint fallback applies only to failures that show the selected URL could not provide
a response, such as DNS failure, connection refusal, loss of network, or a bounded connection
timeout. Bruce must not hide certificate failures, `401` responses, incompatible-server
responses, decoding failures, or other HTTP errors by silently switching URLs.

Read-only, idempotent fetches may be attempted once against the alternate URL. Mutating Home
Assistant commands must not be replayed automatically after an ambiguous transport failure,
because the first endpoint may have performed the command before its response was lost. Before a
future command feature sends a mutation, it should establish a working active URL with a harmless
authenticated check and then send the command once.

The endpoint-selection policy must not depend on a coarse Wi-Fi-versus-cellular check. A device
can use Wi-Fi away from home, a VPN can make the internal address reachable remotely, and an
external URL may also work on the home LAN. Observed request success is the source of truth.

### 7. Initial authenticated API check

After token exchange, setup should perform a small authenticated request such as `GET /api/` or
`GET /api/config` before declaring success. This proves that:

- at least one captured instance URL is usable;
- the token is accepted; and
- the endpoint is a compatible Home Assistant instance.

Setup should preserve both discovered URLs even though the internal URL will usually win this
first check. The first request made after leaving home can then fall back to the external URL and
record it as the new preferred candidate without asking the user to reconfigure Bruce.

The generic REST client can then expose typed state-fetching methods. `GET /api/states` is the
expected first data endpoint, but room-temperature mapping belongs to a subsequent vertical
slice. Home Assistant areas, devices, and entities must be related using their registry data;
friendly names alone are not a reliable room model.

## UI requirements

### Shared setup states

The setup model should represent these states explicitly:

- introduction;
- awaiting local-network permission;
- searching;
- one or more discovered instances;
- no instances found yet;
- manual address entry;
- validating selection;
- authenticating;
- verifying authenticated access;
- connected;
- cancelled; and
- recoverable or terminal error.

The UI must not display an indefinite spinner with no explanation. Searching should continue
while the setup screen is active, and manual entry should remain available without waiting for a
timeout.

### iPhone

- Present connection setup as a short `NavigationStack`.
- Explain why Bruce needs local-network access before starting Bonjour browsing.
- Start discovery from a clear user action so the system permission prompt has context.
- Show discovered homes in a native list with name as the primary label and address/version as
  optional secondary detail.
- If one home is found, preselect it but still require confirmation.
- If several homes are found, require an explicit selection.
- Provide `Enter Address Manually` on the discovery screen.
- Use a system authentication session for Home Assistant sign-in. Do not embed or imitate the
  Home Assistant login form.
- Keep the authentication session cancellable and return to the selected server on cancellation.
- On success, announce that Bruce is connected and move into the first household feature when it
  exists.

All controls need 44-point minimum targets and must work at accessibility Dynamic Type sizes.

### macOS

- Present setup in the initial window using a native form or list rather than an iPhone-sized
  sheet replica.
- Support keyboard navigation through discovered instances, manual entry, retry, and continue.
- Use `ASWebAuthenticationSession` with an appropriate presentation anchor.
- Keep connection management available later from Settings.
- Do not close the setup window while authentication or verification is still in progress.

### Permission and Info.plist requirements

Before starting Bonjour discovery:

- declare `_home-assistant._tcp` in `NSBonjourServices`;
- provide a concise `NSLocalNetworkUsageDescription` explaining that Bruce looks for the user's
  Home Assistant server.

These declarations must be applied only to the platforms that require them and verified on real
iOS and macOS devices. Simulator success is not sufficient evidence for local-network permission
behaviour.

The HTTPS OAuth callback is matched by `ASWebAuthenticationSession`; it does not require Bruce to
register a custom URL scheme. It does require the Associated Domains entitlement for
`webcredentials:bruce.symphonious.net` and the matching public Apple association file.

Permission, privacy, authentication, and recovery language must remain direct and identical in
Bruce and Full Bruce modes.

### Error and recovery behaviour

Provide distinct, actionable presentations for:

- local-network access denied: explain how to enable it in System Settings;
- no server discovered: keep scanning and offer manual entry;
- malformed manual address: keep the entered value and identify what to correct;
- manually entered HTTP address: explain that the local connection is not encrypted and require
  confirmation before sign-in;
- insecure external address: retain it for diagnostics but explain that remote access requires
  HTTPS;
- server unreachable: retry or choose another address;
- certificate failure: explain that the server's secure connection could not be verified;
- authentication cancelled: return to the server confirmation screen without treating it as an
  error;
- authentication rejected or expired: offer sign-in again;
- Home Assistant still onboarding: explain that setup must finish in Home Assistant first; and
- neither saved URL available later: preserve credentials, show offline state, and allow retry or
  connection management.

Do not reveal raw tokens, callback URLs containing codes, internal stack details, or full server
responses in user-facing errors.

### Connection management

Add a Settings connection section when authentication is integrated into the app:

- show the connected Home Assistant instance name and non-secret internal and external URLs;
- show which URL is currently working in secondary diagnostic detail without requiring the user
  to manage an internal/external mode;
- allow the user to test or retry the connection;
- allow reauthentication when credentials are rejected;
- allow changing to another server through the setup flow; and
- provide a confirmed `Disconnect from Home Assistant` action.

Disconnect should revoke the refresh token when possible, delete local credentials regardless of
network availability, cancel active requests and discovery, and return Bruce to its unconnected
state.

### Accessibility

- Announce discovery result-count changes without repeatedly stealing VoiceOver focus.
- Give each discovered instance a clear combined label and selected state.
- Do not use colour alone for reachable, selected, connected, or error states.
- Keep VoiceOver and keyboard focus stable as Bonjour results update.
- Label progress by phase: searching, opening Home Assistant, and verifying connection.
- Respect Reduce Motion and Increase Contrast.

## Security and privacy requirements

- Generate OAuth state with a cryptographically secure random source and compare it exactly.
- Accept callbacks only for the configured redirect target.
- Treat access tokens, refresh tokens, authorization codes, and form bodies as secrets.
- Redact secrets from logs and diagnostics.
- Use ephemeral browser authentication only if product testing shows that preventing shared
  sign-in state is preferable; otherwise use the system session's normal secure cookie handling.
- Send bearer tokens only to the internal and external URLs captured from the user-confirmed
  Home Assistant instance, or to a replacement URL the user explicitly confirms.
- Permit bearer tokens over HTTP only for an internal candidate confirmed under the transport
  policy above.
- Reject redirects that would forward an authorization header to another origin.
- Reject every HTTPS-to-HTTP redirect.
- Store credentials locally in Keychain and do not sync them.
- Never weaken App Transport Security or certificate validation globally.
- Collect no analytics containing home names, local addresses, UUIDs, or authentication outcomes
  tied to a household.

## Testing requirements

### Unit tests

Cover:

- complete, partial, malformed, onboarding, and legacy discovery TXT records;
- deterministic deduplication and ordering;
- preservation of distinct internal and external URLs plus service-resolution fallback;
- manual URL normalization and rejection;
- manual HTTP warning and confirmation;
- rejection of HTTP external candidates and HTTPS-to-HTTP redirects;
- authorization URL query construction;
- callback validation, including missing/mismatched state and OAuth errors;
- exact form bodies for code exchange, refresh, and revocation;
- token decoding and expiry calculation;
- HTTP and Home Assistant error mapping;
- Keychain save, replace, load, delete, and corrupt-record handling through a test store;
- access-token attachment without leaking it into errors;
- last-successful-first URL selection;
- fallback from internal to external and external to internal on qualifying connectivity failures;
- no fallback for TLS, authentication, decoding, or HTTP failures;
- no automatic replay of mutating requests after ambiguous transport failures;
- refresh coalescing for concurrent requests;
- one bounded retry after `401`;
- invalid-refresh cleanup; and
- cancellation at discovery, authentication, refresh, and API-request boundaries.

Tests must use injected discovery, browser-session, credential-store, clock, randomness, and HTTP
boundaries. They must not browse the developer's network, open a real authentication session,
change the developer's Keychain, sleep, retry nondeterministically, or contact a live Home
Assistant instance.

### Integration and manual verification

Use an isolated Home Assistant test instance to verify:

- discovery from iPhone and Mac on the same LAN;
- capture of both advertised URLs while discovery is running;
- local-network permission grant and denial;
- multiple advertised instances;
- manual entry when mDNS is blocked;
- OAuth success, cancellation, rejection, refresh, and revocation;
- app relaunch with saved credentials;
- automatic transition from the internal URL at home to the external URL away from home, and back
  again when only the internal URL is reachable;
- access-token expiry during concurrent API requests;
- server restart and temporary network loss;
- internal HTTP and trusted HTTPS deployments;
- rejection of an HTTP external URL; and
- no token or authorization code appears in captured logs.

Real-device verification is required for Bonjour permissions, callback routing, and Keychain
behaviour.

## Implementation sequence

### Phase 1: Discovery backend

1. Add `HomeAssistantInstance` and discovery record parsing.
2. Add the Network framework browser/resolver adapter.
3. Add discovery streaming, cancellation, deduplication, and tests.
4. Add Bonjour and local-network declarations.

### Phase 2: Discovery UI and manual fallback

1. Add a setup store with explicit discovery states.
2. Add native iPhone and macOS selection flows.
3. Add manual URL entry and validation.
4. Verify permission, accessibility, and cancellation behaviour on devices.

### Phase 3: OAuth backend

1. Add the minimal GitHub Pages source for `bruce.symphonious.net`.
2. Add and validate the Apple association file and Associated Domains entitlement.
3. Configure DNS, the GitHub Pages custom domain, domain verification, and HTTPS.
4. Verify that the root client-ID page, `/auth/` callback route, and Apple association file are
   publicly reachable.
5. Add the fixed release OAuth configuration.
6. Add authorization URL and callback validation.
7. Add token exchange, refresh, revocation, and tests.
8. Add Keychain credential storage and tests.
9. Add the actor-owned authenticated session.

### Phase 4: Authentication UI and connection management

1. Connect setup to `ASWebAuthenticationSession`.
2. Add authentication, verification, cancellation, and recovery states.
3. Add Settings connection status, reauthentication, server change, and disconnect.
4. Verify both Bruce modes use identical security language.

### Phase 5: First authenticated data

1. Add the smallest typed REST methods needed to fetch current entity state.
2. Model Home Assistant area, device, and entity relationships required for room temperatures.
3. Build the room-temperature vertical slice separately, including live, stale, unavailable, and
   error presentation.

Each phase must run the repository's formatting, build, test, and required reviewer cycle before
commit. Networking and asynchronous work require both `code-review` and `concurrency-review`;
setup UI, strings, permissions, and accessibility also require `ui-review`.

## Acceptance criteria

Connection setup is complete when:

- `https://bruce.symphonious.net/` serves the public client-ID page over enforced HTTPS;
- `https://bruce.symphonious.net/auth/` is stable and matches the app's authentication-session
  callback exactly;
- Apple accepts the public Associated Web Credentials file for
  `webcredentials:bruce.symphonious.net`;
- a fresh install can discover all valid Home Assistant advertisements on its LAN;
- every discovered instance retains both valid advertised URLs;
- the user can connect by manual URL when discovery is unavailable;
- the user confirms the server before Bruce opens authentication;
- OAuth callbacks cannot succeed with a missing or mismatched state;
- tokens are exchanged, refreshed, stored, and removed without appearing in logs or non-secure
  storage;
- concurrent API calls share one refresh and recover from a single expired access token;
- authenticated read requests automatically use whichever captured URL is reachable, preferring
  the last one that succeeded;
- moving between the home LAN and an external network does not require manual server switching;
- app relaunch restores an authenticated session from Keychain;
- disconnect revokes credentials when possible and always clears local access;
- iPhone and Mac expose native, accessible recovery paths for every setup state; and
- an authenticated Home Assistant API check succeeds before the UI reports that Bruce is
  connected.

## Resolved implementation decisions

- Local HTTP is allowed only for a user-confirmed internal candidate.
- External access requires trusted HTTPS.
- Privately issued and self-signed HTTPS certificates are rejected.
- Changing servers preserves the working connection until the replacement authenticates and
  verifies successfully.

## References

- [Home Assistant instance discovery](https://developers.home-assistant.io/docs/api/instance_discovery/)
- [Home Assistant authentication API](https://developers.home-assistant.io/docs/auth_api/)
- [Home Assistant REST API](https://developers.home-assistant.io/docs/api/rest/)
- [Home Assistant native app connection setup](https://developers.home-assistant.io/docs/api/native-app-integration/setup/)
- [Apple web authentication sessions](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession)
- [GitHub Pages custom domains](https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/about-custom-domains-and-github-pages)
