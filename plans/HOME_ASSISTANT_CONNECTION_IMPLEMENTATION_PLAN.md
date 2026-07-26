# Home Assistant Connection Implementation Plan

## Status

Ready for implementation after the manual decision and infrastructure checkpoints below.

This document turns
[`HOME_ASSISTANT_CONNECTION_PLAN.md`](HOME_ASSISTANT_CONNECTION_PLAN.md) into executable work. The
specification remains authoritative for product behaviour, security, and acceptance criteria.

## Delivery outcome

At the end of this plan, Bruce will:

- discover Home Assistant instances over Bonjour;
- retain both advertised internal and external URLs;
- support manual server entry;
- authenticate through Home Assistant OAuth;
- store credentials in the device Keychain;
- restore an authenticated session after relaunch;
- choose the last successful server URL and fall back safely for read requests;
- verify authenticated Home Assistant access before reporting a connection;
- let the user reauthenticate, change server, or disconnect; and
- provide the backend boundary needed by the first data feature.

Room-temperature retrieval and presentation are a follow-on vertical slice. This plan ends with a
typed authenticated connection check, not an entity browser or temperature UI.

## Execution rules

- Perform all work in the existing `feature/home-assistant-client` worktree.
- Keep each milestone independently buildable and testable on iOS and macOS.
- Do not edit `Bruce.xcodeproj`; add source through the existing synchronized `App` and `Tests`
  directories and regenerate with `just generate`.
- Do not add third-party packages unless a platform API proves insufficient and the user approves
  the dependency.
- Do not put real server URLs, home names, OAuth codes, or tokens in the repository.
- Complete the formatting, build, test, and reviewer gate listed for a milestone before committing
  it.
- Fix every reviewer finding and rerun the affected reviewers until they report no findings.

## Decisions before implementation

### Manual decision 1: local HTTP policy

Home Assistant commonly advertises an internal URL such as
`http://homeassistant.local:8123`. Using it for OAuth and API requests sends bearer credentials
without TLS on the local network.

Before Milestone 2, the user must select one policy:

1. **Allow discovered local HTTP:** accept `http://` only when it came from a user-confirmed
   `_home-assistant._tcp.local.` advertisement or its resolved service endpoint. Continue to
   require HTTPS for external URLs. This provides the easiest compatibility with default Home
   Assistant installations.
2. **Require HTTPS everywhere:** reject HTTP URLs and instruct the user to configure trusted HTTPS
   for the Home Assistant instance. This is the strongest transport policy but makes common local
   installations require extra setup.

Do not infer this choice from implementation convenience. Record the selected policy in the
specification before networking code is committed.

### Decisions already resolved

- Client ID: `https://bruce.symphonious.net/`
- OAuth redirect: `https://bruce.symphonious.net/auth/`
- Self-signed and privately issued certificates: reject by default.
- Server replacement: keep the current working connection until the replacement authenticates
  and verifies successfully.
- Credential sync: device-only Keychain; no iCloud synchronization.
- Endpoint selection: observed success, not Wi-Fi or cellular identity.

## Dependency order

```text
Milestone 0: manual policy decision
        |
        +------------------------------+
        |                              |
        v                              v
Milestone 1: OAuth website      Milestone 2: discovery backend
        |                              |
        |                              v
        |                       Milestone 3: discovery UI
        |                              |
        +---------------+--------------+
                        |
                        v
             Milestone 4: OAuth backend
                        |
                        v
          Milestone 5: authenticated session
                        |
                        v
           Milestone 6: authentication UI
                        |
                        v
          Milestone 7: connection management
                        |
                        v
           Milestone 8: end-to-end validation
```

The website and discovery backend can be developed independently, but OAuth cannot be verified
until the website, DNS, and HTTPS checkpoints are complete.

## Milestone 0: preflight and baselines

### Implementation work

1. Record the selected local HTTP policy in the specification.
2. Confirm the branch starts clean and rebased or merged from the intended `main`.
3. Run and capture the existing tests before changing production code:

   ```sh
   mkdir -p .agent-tmp
   just test 2>&1 | tee .agent-tmp/home-assistant-baseline-tests.txt
   ```

4. Confirm the installed SDK exposes:
   - `NWBrowser` Bonjour browsing and TXT records;
   - `ASWebAuthenticationSession.Callback.https(host:path:)`;
   - Keychain Services; and
   - the required iOS and macOS local-network privacy keys.
5. Confirm GitHub Pages is available for the private `ajsutton/bruce` repository under the
   account's current GitHub plan. If it is unavailable, stop and ask the user to choose between a
   plan change and a separate public website repository. Do not make the application repository
   public.

### Exit criteria

- The HTTP policy is documented.
- Baseline tests pass.
- Required platform APIs and GitHub Pages availability are confirmed.

### Commit

Commit only if the specification changed to record the HTTP policy.

## Milestone 1: minimal OAuth website

### Files

Create:

```text
docs/.nojekyll
docs/CNAME
docs/index.html
docs/auth/index.html
```

### Implementation work

1. Add `bruce.symphonious.net` as the sole contents of `docs/CNAME`.
2. Add a minimal, accessible root page that:
   - identifies Bruce as a native iPhone and Mac client for a Home Assistant-backed home;
   - uses existing Bruce brand colours and system font fallbacks;
   - contains no claims about unimplemented product functionality;
   - has useful title, description, viewport, and colour-scheme metadata; and
   - works without scripts, cookies, analytics, forms, remote fonts, or remote images.
3. Add a minimal `/auth/` fallback page that:
   - says authentication should return to Bruce;
   - offers no token input or account controls;
   - does not read, render, persist, forward, or transform query parameters; and
   - contains no JavaScript or third-party resources.
4. Verify both pages with a local static HTTP server at root and `/auth/`.
5. Check keyboard navigation, text scaling, dark mode, narrow layout, and semantic heading order.
6. Confirm no source or generated page contains a real OAuth code, state, token, home URL, or
   household identity.

### Automated checks

- Add a lightweight repository test or script that verifies:
  - `docs/CNAME` has the exact custom domain;
  - both HTML files exist;
  - neither page includes scripts, forms, analytics, or external assets; and
  - required title, description, language, and viewport metadata are present.
- Run `git diff --check`.

### Manual checkpoint: publish the site

Complete the instructions in **Manual setup instructions A-C** after the website commit reaches
`main`. OAuth implementation may continue locally, but real authentication cannot pass its final
gate until the public URLs work over HTTPS.

### Reviewers

- `code-review` for repository structure and scope.
- `ui-review` for public copy, accessibility, and Bruce branding.

### Commit

Suggested commit: `Add minimal Bruce OAuth website`

## Milestone 2: discovery model and backend

### Anticipated source boundaries

Names may be adjusted during review, but responsibilities should remain separated:

```text
App/HomeAssistant/Discovery/HomeAssistantInstance.swift
App/HomeAssistant/Discovery/HomeAssistantDiscoveryRecord.swift
App/HomeAssistant/Discovery/HomeAssistantDiscoveryClient.swift
App/HomeAssistant/Discovery/NetworkHomeAssistantDiscovery.swift
Tests/HomeAssistantDiscoveryRecordTests.swift
Tests/HomeAssistantDiscoveryClientTests.swift
```

### Implementation work

1. Add immutable, `Sendable`, `Equatable` values for:
   - stable instance UUID;
   - display name;
   - optional version;
   - optional internal URL;
   - optional external URL; and
   - onboarding state.
2. Parse Home Assistant TXT metadata without accepting the obsolete password flag.
3. Preserve valid internal and external URLs independently and deduplicate identical candidates.
4. Use the deprecated `base_url` only as a final compatibility candidate.
5. Resolve the Bonjour service host and port when no internal URL is advertised.
6. Wrap `NWBrowser` behind the smallest testable discovery boundary.
7. Expose an asynchronous stream of deterministic discovery snapshots.
8. Deduplicate instances by UUID and order by display name then UUID.
9. Cancel browsing, resolution, handlers, and continuations when the consumer stops.
10. Map permission denial, browser failure, invalid advertisements, and cancellation distinctly.
11. Add the required Bonjour and local-network usage keys to the applicable Info.plists.
12. Apply the selected local HTTP policy without weakening TLS or App Transport Security
    globally.

### Unit tests

Cover:

- complete internal-and-external advertisements;
- only-internal, only-external, and neither-URL advertisements;
- duplicate URL and UUID records;
- malformed URLs and TXT values;
- landing-page advertisements;
- missing version;
- `base_url` compatibility;
- resolved-service fallback;
- stable ordering;
- result updates and removal;
- permission and browser failures; and
- stream cancellation and cleanup.

Tests must use synthetic records and an injected browser adapter. They must not browse the
developer's LAN.

### Quality gate

```sh
just format
just format-check
just build
just test
```

Reviewers:

- `code-review`
- `concurrency-review`

### Commit

Suggested commit: `Add Home Assistant server discovery`

## Milestone 3: discovery setup UI and manual entry

### Anticipated source boundaries

```text
App/HomeAssistant/Setup/HomeAssistantSetupStore.swift
App/HomeAssistant/Setup/HomeAssistantSetupView.swift
App/HomeAssistant/Setup/HomeAssistantServerAddress.swift
Tests/HomeAssistantSetupStoreTests.swift
Tests/HomeAssistantServerAddressTests.swift
```

Use platform-specific view files if a shared view makes either iPhone or Mac behaviour unnatural.

### Implementation work

1. Add an explicit setup state machine for introduction, permission, searching, results, manual
   entry, validation, authentication handoff, verification, completion, cancellation, and errors.
2. Start discovery only after the user chooses the clearly explained local-network action.
3. Keep manual address entry available while discovery continues.
4. Preselect one result but require confirmation; require explicit selection among multiple
   results.
5. Normalize manual URLs and reject credentials, fragments, endpoint suffixes, and unsupported
   schemes.
6. Preserve typed input after validation errors.
7. Keep VoiceOver and keyboard focus stable when discovery results change.
8. Stop discovery when the setup screen no longer owns it.
9. Provide deterministic preview and test dependencies; never browse from previews.

### Unit and UI tests

Unit-test every setup state transition, stale-result protection, replacement, and cancellation.

Add one UI test only if real navigation/focus behaviour cannot be proven below the UI:

```text
Launch disconnected
Start discovery with a deterministic seed
Choose a discovered home
Reach the confirmation screen
```

If a UI test is added, create typed screen drivers, central identifiers, finite condition waits,
and failure artefacts as required by `UI_TEST_GUIDE.md`.

### Quality gate

```sh
just format
just format-check
just build
just test
```

Reviewers:

- `code-review`
- `concurrency-review`
- `ui-review`
- `ui-test-review` only if UI tests, drivers, seeds, or identifiers changed

### Commit

Suggested commit: `Add Home Assistant discovery setup`

## Milestone 4: OAuth protocol and credential storage

### Anticipated source boundaries

```text
App/HomeAssistant/Authentication/HomeAssistantOAuthConfiguration.swift
App/HomeAssistant/Authentication/HomeAssistantAuthenticationClient.swift
App/HomeAssistant/Authentication/HomeAssistantCredentials.swift
App/HomeAssistant/Authentication/HomeAssistantCredentialStore.swift
App/HomeAssistant/Authentication/KeychainHomeAssistantCredentialStore.swift
Tests/HomeAssistantAuthenticationClientTests.swift
Tests/HomeAssistantCredentialStoreTests.swift
```

### Implementation work

1. Hard-code the release OAuth client ID and redirect URL in one immutable configuration value.
2. Generate OAuth state with a cryptographically secure random source.
3. Build the authorization URL against the confirmed reachable instance URL.
4. Validate callback scheme, host, port, path, OAuth error, state, and code exactly.
5. Form-encode authorization-code, refresh-token, and revocation requests.
6. Decode token responses and calculate expiry using an injected clock.
7. Preserve useful protocol errors while redacting request bodies and secrets.
8. Define a versioned credential value containing both instance URLs and the last successful URL.
9. Store credentials in a non-synchronizable, device-only Keychain item available after first
   unlock.
10. Make Keychain replacement atomic from the caller's perspective.
11. Delete corrupt or rejected credentials only under the behaviours defined by the specification.
12. Keep browser presentation outside the protocol client.

### Unit tests

Cover:

- exact client ID and redirect query encoding;
- high-entropy state injection and callback match/mismatch;
- missing code and OAuth error callbacks;
- exact token and revoke form bodies;
- successful and malformed token responses;
- server error descriptions without secret leakage;
- expiry calculations under an injected clock;
- Keychain save, replace, load, delete, and corrupt data;
- no iCloud synchronization attributes; and
- cancellation of token operations.

Use an injected HTTP loader and an in-memory credential-store double. Unit tests must not change
the developer's Keychain or contact a Home Assistant server.

### Quality gate

```sh
just format
just format-check
just build
just test
```

Reviewers:

- `code-review`
- `concurrency-review`

### Commit

Suggested commit: `Add Home Assistant OAuth and credential storage`

## Milestone 5: authenticated session and endpoint routing

### Anticipated source boundaries

```text
App/HomeAssistant/API/HomeAssistantAPIClient.swift
App/HomeAssistant/API/HomeAssistantAPIError.swift
App/HomeAssistant/Authentication/HomeAssistantSession.swift
Tests/HomeAssistantAPIClientTests.swift
Tests/HomeAssistantSessionTests.swift
```

### Implementation work

1. Add an actor-owned session as the single mutable owner of credentials and refresh work.
2. Attach bearer tokens only to requests derived from confirmed internal or external URLs.
3. Prefer the last successful URL.
4. For idempotent reads, try the alternate URL once after DNS, connection, offline, or bounded
   connection-timeout failure.
5. Do not switch silently for TLS, authentication, HTTP, compatibility, or decoding failures.
6. Do not automatically replay mutating requests after ambiguous transport failure.
7. Coalesce concurrent refresh requests.
8. Refresh before expiry and retry one read after a refreshable `401`.
9. Prevent stale refresh results from replacing newer credentials.
10. Persist the new credential and last-successful URL only after success.
11. Clear invalid-refresh credentials and surface reauthentication.
12. Add a typed authenticated `GET /api/` connection check.
13. Preserve cancellation through routing, refresh, and HTTP loading.

### Unit tests

Cover:

- bearer-header construction and origin restrictions;
- internal-first initial check after discovery;
- internal-to-external and external-to-internal fallback;
- last-successful-first behaviour after a switch;
- all non-fallback error classes;
- one bounded fallback;
- no mutation replay;
- coalesced refresh;
- pre-expiry refresh;
- one `401` retry;
- invalid-refresh cleanup;
- stale-result protection;
- persistence failures; and
- cancellation at every suspension point.

### Quality gate

```sh
just format
just format-check
just build
just test
```

Reviewers:

- `code-review`
- `concurrency-review`

### Commit

Suggested commit: `Add authenticated Home Assistant sessions`

## Milestone 6: system authentication UI

### Implementation work

1. Add a small authentication-session presenter around `ASWebAuthenticationSession`.
2. Match only HTTPS callbacks for host `bruce.symphonious.net` and path `/auth/`.
3. Provide the correct presentation anchor on iPhone and Mac.
4. Keep the session owned and cancellable for the duration of setup.
5. Connect confirmed discovery/manual selection to:
   - authorization;
   - callback validation;
   - token exchange;
   - Keychain save;
   - authenticated connection check; and
   - setup completion.
6. Treat user cancellation as a return to confirmation, not a technical failure.
7. Present distinct recovery for rejected auth, inactive user, unavailable server, invalid
   callback, and failed verification.
8. Never show or log callback URLs, codes, state, or tokens.
9. Restore saved credentials on launch and enter connected or reauthentication state honestly.

### Tests

- Unit-test orchestration with injected browser, authentication, credential, and session
  boundaries.
- Test cancellation, replacement, stale callbacks, rejected state, persistence failure, and
  verification failure.
- Add or extend one deterministic UI journey only where system presentation/navigation needs
  coverage. Do not automate a real Home Assistant login in the regular test suite.

### Quality gate

```sh
just format
just format-check
just build
just test
```

Reviewers:

- `code-review`
- `concurrency-review`
- `ui-review`
- `ui-test-review` if UI-test infrastructure changed

### Commit

Suggested commit: `Connect Home Assistant authentication setup`

## Milestone 7: connection management

### Implementation work

1. Add a Settings section showing:
   - connected instance name;
   - internal and external URLs;
   - currently successful route as secondary diagnostic detail; and
   - connection or reauthentication state.
2. Add retry/test connection.
3. Add reauthentication without deleting the current connection prematurely.
4. Add change-server flow that swaps credentials only after the new connection verifies.
5. Add confirmed disconnect.
6. On disconnect:
   - cancel active setup, discovery, refresh, and API work;
   - revoke the refresh token through an available endpoint when possible;
   - delete local credentials regardless of network success; and
   - return to disconnected setup state.
7. Keep permission, security, and recovery language identical in Bruce and Full Bruce modes.

### Tests

Cover retry, successful and failed reauthentication, safe server replacement, online and offline
disconnect, revocation failure, cancellation, and restored settings state.

### Quality gate

```sh
just format
just format-check
just build
just test
```

Reviewers:

- `code-review`
- `concurrency-review`
- `ui-review`
- `ui-test-review` if UI-test infrastructure changed

### Commit

Suggested commit: `Add Home Assistant connection management`

## Milestone 8: integration and real-device validation

### Automated final gate

Capture the final complete run:

```sh
mkdir -p .agent-tmp
just format
just format-check
just build
just test 2>&1 | tee .agent-tmp/home-assistant-final-tests.txt
```

Run the final reviewers together after the code is stable:

- `code-review`
- `concurrency-review`
- `ui-review`
- `ui-test-review` if applicable

Fix every finding and repeat the relevant build, tests, and reviewers until clean.

### Manual validation matrix

Follow **Manual setup instructions D-F** and record results for:

| Scenario | iPhone | Mac |
| --- | --- | --- |
| Local-network permission allowed | Required | Required |
| Local-network permission denied and recovered | Required | Required |
| One discovered instance with both URLs | Required | Required |
| Multiple discovered instances | Required | Required |
| Manual URL fallback | Required | Required |
| OAuth success | Required | Required |
| OAuth cancellation | Required | Required |
| Relaunch with saved credentials | Required | Required |
| Internal URL at home | Required | Required |
| External fallback away from home | Required | Required |
| Return to internal-only reachability | Required | Required |
| Temporary server outage | Required | Required |
| Reauthentication | Required | Required |
| Offline disconnect | Required | Required |
| VoiceOver and keyboard navigation | VoiceOver | Keyboard and VoiceOver |

No token, code, state, home name, UUID, or private URL may appear in captured unified logs or test
artefacts.

### Final commit

Commit only validation-driven fixes. Do not create an empty validation commit.

## Manual setup instructions

The implementation agent must present these instructions to the user at the indicated checkpoint
and clearly identify which steps remain incomplete. It may verify public DNS and URLs read-only,
but must not assume access to the user's DNS provider or Home Assistant administrator account.

### A. Verify the custom domain with GitHub

Do this before assigning the custom domain to the repository:

1. Sign in to GitHub as `ajsutton`.
2. Open the personal account **Settings** page, not the repository settings.
3. Under **Code, planning, and automation**, open **Pages**.
4. Select **Add a domain** and enter `bruce.symphonious.net`.
5. GitHub will display a DNS TXT record name and value. Copy both exactly.
6. In the DNS provider for `symphonious.net`, add that TXT record.
7. Wait for DNS propagation, return to GitHub's Pages settings, and select **Verify**.
8. Keep the TXT record permanently; removing it removes takeover protection.

Do not use a wildcard DNS record for this setup.

### B. Point the subdomain to GitHub Pages

In the DNS provider for `symphonious.net`:

1. Remove any conflicting `A`, `AAAA`, or `CNAME` record for the `bruce` host.
2. Add:

   ```text
   Type:   CNAME
   Name:   bruce
   Target: ajsutton.github.io
   ```

3. If the DNS provider offers HTTP proxying, leave the record as ordinary DNS while GitHub issues
   and validates its certificate.
4. Do not change records for the `symphonious.net` apex or unrelated subdomains.

DNS propagation can take up to 24 hours.

### C. Enable GitHub Pages for `ajsutton/bruce`

Do this after the website files have reached `main`:

1. Open `https://github.com/ajsutton/bruce/settings/pages`.
2. Under **Build and deployment**, choose **Deploy from a branch**.
3. Choose branch `main`, folder `/docs`, then save.
4. Confirm the custom domain is `bruce.symphonious.net`. The committed `docs/CNAME` should supply
   it; enter it manually only if GitHub does not.
5. Wait for the Pages deployment and TLS certificate.
6. Enable **Enforce HTTPS** as soon as GitHub makes it available.
7. Confirm in a private browser window:
   - `https://bruce.symphonious.net/` loads without a certificate warning; and
   - `https://bruce.symphonious.net/auth/` loads without a certificate warning.

If GitHub does not offer Pages for the private repository, stop. Do not make the repository
public. Choose a supported account plan or approve a separate public website repository.

### D. Configure the Home Assistant URLs

In the Home Assistant instance used for testing:

1. Sign in as an administrator.
2. Open **Settings > System > Network**.
3. Under **Home Assistant URL**, set the local-network address in the local field.
4. Set the externally reachable trusted HTTPS address in the Internet field.
5. Save.
6. Restart Home Assistant if its discovery advertisement does not update.
7. Confirm the external URL works from a device that is not connected to the home LAN before
   relying on it for Bruce.

The URLs may contain a scheme, host, and port, but no path. Do not expose Home Assistant directly
to the Internet without an appropriately secured remote-access configuration.

### E. Perform the first OAuth test

No central Home Assistant developer registration or client secret is required.

1. Install a development build of Bruce on the test device.
2. Start connection setup while connected to the same LAN as Home Assistant.
3. Approve the local-network permission.
4. Confirm Bruce displays both the internal and external URLs from the discovery record.
5. Select the instance and continue.
6. In the system authentication session, sign in to Home Assistant and approve access.
7. Do not copy credentials, codes, or tokens into issue comments, chat, screenshots, or test
   fixtures.
8. Confirm Bruce reports connected only after its authenticated API check succeeds.

### F. Verify automatic internal/external switching

1. At home, confirm Bruce connects and records the internal URL as successful.
2. Close and reopen Bruce to prove Keychain restoration works.
3. Leave the home network or disable Wi-Fi so the internal address is unreachable.
4. Open Bruce and confirm a read-only connection check falls back to the external URL without
   asking for another login.
5. Reopen the connection settings and confirm the external route is now the successful route.
6. Return to a network where only the internal URL is reachable.
7. Confirm Bruce falls back to the internal URL and remembers it again.
8. Review captured logs and confirm they contain no token, OAuth code, state, home UUID, or full
   private URL.

## Completion checklist

- [ ] Local HTTP policy selected and documented.
- [ ] Baseline tests captured.
- [ ] Minimal website committed and merged.
- [ ] GitHub domain verified.
- [ ] DNS CNAME configured.
- [ ] GitHub Pages enabled from `main` and `/docs`.
- [ ] HTTPS enforced at both public routes.
- [ ] Discovery backend and tests complete.
- [ ] Discovery/manual-entry UI complete.
- [ ] OAuth and Keychain backend complete.
- [ ] Authenticated session and endpoint routing complete.
- [ ] Authentication UI complete.
- [ ] Connection management complete.
- [ ] iPhone and Mac automated gates pass.
- [ ] Required reviewers report no findings.
- [ ] Real-device manual matrix complete.
- [ ] Every intended change committed.
