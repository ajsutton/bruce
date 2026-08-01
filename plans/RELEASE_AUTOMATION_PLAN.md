# Release Automation Plan

## Status

Ready for implementation, subject to the Apple signing and GitHub secret checkpoints below.

This plan establishes Bruce release-candidate and final-release pipelines based on
`../moolah-project/moolah-native`. It covers automatic iOS upload to TestFlight, direct macOS
distribution from the same RC tag, promotion of a tested RC to the App Store and a final GitHub
release, and the post-release version bump. It does not authorize creating a tag, changing Apple
signing state, submitting for review, or uploading a build by itself.

## Delivery outcome

Creating an approved GitHub prerelease with a tag such as `v0.1.0-rc.1` will start one workflow
against that exact commit. The workflow will:

1. derive marketing version `0.1.0` from the tag;
2. obtain the next build number from TestFlight;
3. build and upload the signed iOS app to TestFlight;
4. build the macOS app with the same marketing version and build number;
5. sign the Mac app with `Developer ID Application`;
6. submit it to Apple's notarisation service and wait for acceptance;
7. staple the notarisation ticket to `Bruce.app`;
8. create `Bruce-0.1.0.zip`; and
9. attach the zip, `build-number.txt`, and an attested release manifest to the GitHub prerelease.

The Mac zip is for direct distribution. The Mac app will not be submitted to the Mac App Store.
TestFlight remains the iOS distribution channel.

After an RC has passed smoke testing, creating an approved final GitHub release such as `v0.1.0`
at the same commit will start a second workflow. That workflow will:

1. prove the final tag points at the latest RC for that marketing version;
2. read the tested build number from the RC release;
3. submit that existing TestFlight build for App Store review with automatic release after Apple
   approves it;
4. copy the already-tested notarised Mac zip from the RC prerelease to the final GitHub release;
   and
5. open and immediately squash-merge a narrowly scoped post-release marketing-version bump PR.

The final workflow will not rebuild either platform. The binaries tested as the RC are the
binaries promoted as final.

## Release conventions

- RC tags use `v<MAJOR>.<MINOR>.<PATCH>-rc.<N>`.
- An RC tag is permanent after it has been pushed. A failed or obsolete RC is documented and
  superseded by a new RC; it is not deleted or moved.
- The tag, GitHub prerelease, TestFlight build, and Mac zip all identify the same commit.
- The RC workflow creates and attests a manifest binding the tag, commit SHA, marketing version,
  build number, Mac filename, and Mac SHA-256. Final promotion verifies that attestation and every
  bound value before using the build or asset.
- iOS and macOS use the base marketing version from the tag and the same monotonically increasing
  build number.
- The canonical tagging path is the checked-in `just release-create-rc` command after
  `just release-preflight`, not a raw `git tag` command.
- Final tags use `v<MAJOR>.<MINOR>.<PATCH>` and point at the exact commit of the latest RC for that
  version.
- The canonical final-promotion path is `just release-create-final`, which refuses to promote an
  older RC or a different commit.
- A successful upload means the iOS build reached App Store Connect. Apple may still be processing
  it before it appears in TestFlight.
- Initial delivery to internal or external tester groups is configured separately in App Store
  Connect. This pipeline will not silently distribute a build to external testers.
- Final App Store release is automatic only after App Review approval. A workflow success means
  the submission was made; it does not mean Apple approved or released it immediately.

## Responsibility summary

### Work Codex can perform

Codex can implement and review all repository-owned automation:

- add Fastlane and its locked Ruby dependencies;
- add iOS App Store and macOS Developer ID lanes;
- configure target-scoped Release signing in `project.yml`;
- add build-number protection and tests;
- add the RC tag workflow;
- add the final-promotion workflow;
- add release helper scripts and `just` targets;
- add the durable release runbook;
- run formatting, unsigned builds, tests, script tests, and required reviewers;
- commit the reviewed repository changes;
- create the empty GitHub `rc-release` and `production-release` environments if the user authorizes
  those GitHub settings changes;
- inspect secret names, workflow state, and release assets without reading secret values; and
- after the release approval gate, create the approved prerelease/tag and monitor its workflow;
- after the final-release approval gate, create the approved final release/tag and monitor its
  workflow; and
- create the post-release bump PR automation.

### Steps the user must perform manually

The user must perform account- and secret-bearing setup that Codex cannot safely infer or recover:

- confirm the Apple Developer team and its legal/account agreements are active;
- create or confirm the Apple App ID and App Store Connect app record;
- enable required capabilities for the production bundle identifier;
- create or select an App Store Connect API key and retain its `.p8` private key;
- create a dedicated private Match repository for Bruce with its own encryption password and
  least-privilege access credential;
- provide writable access to that repository for the one-time certificate/profile bootstrap;
- place secret values in the protected GitHub release environments;
- configure TestFlight tester groups and beta-review information as desired;
- complete the App Store product page, privacy, pricing, review, and release metadata before final
  promotion;
- provide a working App Review Home Assistant environment and temporary credentials, or approve
  and verify a fully featured in-app demo mode, for Bruce's account-dependent functionality;
- enable GitHub Actions to create pull requests for the post-release bump;
- explicitly approve any action that creates or repairs certificates or provisioning profiles;
- explicitly approve the first RC's version, commit SHA, tag, notes, and distribution path before
  the tag is created;
- explicitly approve the final version, RC pairing, commit SHA, final notes, App Store submission,
  automatic-release choice, and post-release bump before the final tag is created; and
- install and smoke-test the TestFlight build and downloaded Mac zip.

Codex must never print or commit the `.p8` key, Match password, Git credentials, certificates,
private keys, or provisioning-profile contents.

## Dependency order

```text
Milestone 1: repository release infrastructure
        |
        v
Milestone 2: Apple account and signing setup (manual)
        |
        v
Milestone 3: GitHub environment secrets (manual)
        |
        v
Milestone 4: signed validation without release tagging
        |
        v
Milestone 5: first approved RC tag and automated distribution
        |
        v
Milestone 6: user smoke test and pipeline acceptance
        |
        v
Milestone 7: final-release readiness (manual)
        |
        v
Milestone 8: approved final promotion
        |
        v
Milestone 9: post-release verification
```

## Milestone 1: repository release infrastructure

**Owner:** Codex

### Files

Add or update:

```text
.github/workflows/release-rc.yml
.github/workflows/release-final.yml
Gemfile
Gemfile.lock
fastlane/Appfile
fastlane/Fastfile
fastlane/Matchfile
guides/RELEASE_GUIDE.md
justfile
project.yml
scripts/check-release-build-number.sh
scripts/install-ci-tools.sh
scripts/lib/release-common.sh
scripts/release-create-rc.sh
scripts/release-create-final.sh
scripts/release-next-version.sh
scripts/release-preflight.sh
scripts/release-status.sh
scripts/release-wait.sh
scripts/tests/test-release-common.sh
```

Names may be adjusted during review, but the responsibilities and safety gates must remain.

### Project signing configuration

1. Keep `DEVELOPMENT_TEAM` environment-driven.
2. Configure the iOS target's Release settings with:
   - `CODE_SIGN_STYLE: Manual`;
   - `CODE_SIGN_IDENTITY: Apple Distribution`;
   - `CODE_SIGN_ENTITLEMENTS: App/Bruce.entitlements`; and
   - `PROVISIONING_PROFILE_SPECIFIER: ${IOS_PROVISIONING_PROFILE}`.
3. Configure the macOS target's Release settings with:
   - `CODE_SIGN_STYLE: Manual`;
   - `CODE_SIGN_IDENTITY: Developer ID Application`;
   - `CODE_SIGN_ENTITLEMENTS: App/Bruce.entitlements`;
   - `PROVISIONING_PROFILE_SPECIFIER: ${MAC_PROVISIONING_PROFILE}`; and
   - `ENABLE_HARDENED_RUNTIME: YES`.
4. Keep signing settings scoped to application targets so they do not leak into test or package
   targets.
5. Add a Release-only pre-build guard that rejects the placeholder build number `1`. Fastlane
   must set a real build number before either distribution build can succeed.
6. Continue generating `Bruce.xcodeproj` from `project.yml`; never check in or edit the generated
   project directly.

### Fastlane iOS work

1. Configure App Store Connect API-key authentication from environment variables.
2. Require a team App Store Connect API key. An individual key is not valid for the provisioning
   and notarisation operations used by this pipeline.
3. Add `ios certificates` using Match type `appstore` for `net.symphonious.bruce`.
4. Keep Match read-only in CI; certificate/profile creation is a separately approved bootstrap
   action.
5. Bake Match's profile name into `IOS_PROVISIONING_PROFILE` and regenerate the project.
6. Query `latest_testflight_build_number` immediately before allocation, increment it by one, and
   apply it after the final project generation.
7. Build scheme `Bruce-iOS` with export method `app-store`.
8. Add a validation lane that validates an IPA without intentionally distributing it to testers.
9. Add `ios beta` to upload the IPA with API-key authentication and return without blocking on
   App Store Connect processing.
10. Add `ios submit_review` that accepts an explicit version and build number, selects that existing
   TestFlight build, submits it for review without uploading a replacement binary, skips metadata
   and screenshots, supplies the reviewed export-compliance answers, and requests automatic
   release after approval.

### Fastlane macOS work

1. Add `mac certificates` using Match type `developer_id`, platform `macos`, for
   `net.symphonious.bruce`.
2. Bake Match's profile name into `MAC_PROVISIONING_PROFILE` and regenerate the project.
3. Apply the build number captured from the iOS lane after the final project generation.
4. Build scheme `Bruce-macOS`, configuration `Release`, with export method `developer-id`.
5. Confirm `Bruce.app` exists and fail clearly if it does not.
6. Create a temporary notarisation zip with `ditto -c -k --keepParent`.
7. Materialize the base64 App Store Connect key into a temporary `.p8` file for `notarytool`.
8. Submit with `xcrun notarytool submit --wait`.
9. Staple and validate the ticket with `xcrun stapler`.
10. Verify the signed app with `codesign --verify --deep --strict` and Gatekeeper assessment.
11. Create `build/Bruce-<version>.zip` from the stapled app using `ditto`.
12. Remove temporary key and intermediate notarisation files even when the lane fails.

### GitHub Actions RC workflow

1. Trigger only on tags matching `v[0-9]+.[0-9]+.[0-9]+-rc.[0-9]+`.
2. Check out the exact tag with full tag history.
3. Use Bruce's established `xcode-27` runner label unless repository CI changes before
   implementation.
4. Set an explicit timeout and use the `rc-release` environment for secret scoping, without a
   required-reviewer deployment gate.
5. Request only the GitHub permissions required by the workflow, including `contents: write` for
   release-asset upload and the identity/attestation permissions needed for GitHub artifact
   attestations.
6. Install the pinned XcodeGen version and locked Ruby bundle.
7. Validate the tag and derive its base marketing version.
8. Use a repository-wide RC release concurrency group with `cancel-in-progress: false` so two tags
   cannot allocate the same TestFlight build number.
9. Run `bundle exec fastlane ios beta`, re-querying the latest build immediately before allocation.
10. Read the resulting build number from the generated Xcode project and save it as
   `build/build-number.txt`;
11. Run `bundle exec fastlane mac zip` with the same version and build number.
12. Create `release-manifest.json` containing the RC tag, commit SHA, marketing version, build
    number, Mac filename, and Mac SHA-256.
13. Create GitHub build-provenance attestations for both the Mac zip and release manifest, bound to
    this repository, workflow, tag, and commit.
14. Attach `Bruce-<version>.zip`, `build-number.txt`, and `release-manifest.json` to the existing
    GitHub prerelease. Refuse to replace an existing RC manifest or zip; a changed binary requires
    a new RC tag.
15. Optionally retain the IPA as a short-lived Actions artefact for diagnostics. The IPA is not a
   public GitHub release asset.

The workflow must not include Moolah's CloudKit schema gates, Mac extension profiles, or monthly
automatic tagging because Bruce has no corresponding use case.

### GitHub Actions final workflow

1. Trigger only on final tags matching `v[0-9]+.[0-9]+.[0-9]+`.
2. Check out full tag history and use the `production-release` environment for secret scoping,
   without a required-reviewer deployment gate.
3. Resolve the latest RC tag for the final marketing version.
4. Fail unless the final tag and latest RC tag point at the same commit.
5. Download the RC manifest, build number, and Mac zip.
6. Verify the GitHub attestations were produced by Bruce's RC workflow for this repository and
   commit, then verify every manifest field, the build-number file, and the Mac zip digest agree.
   Fail before App Store submission if any value differs.
7. Run the Fastlane submission lane for that exact marketing version and build number. Do not
   build or upload another IPA.
8. Attach the exact verified `Bruce-<version>.zip` from the paired RC prerelease unchanged
   to the existing final GitHub release.
9. Verify the copied asset's digest before and after upload so final promotion cannot silently
   substitute a different Mac binary.
10. Open an idempotent post-release version-bump PR from current `origin/main`, defaulting to the
   next minor version and clearly documenting how to choose a major, patch, or explicit version.
11. Immediately squash-merge that PR without waiting for CI or a merge queue. This exception is
    limited to the mechanical `MARKETING_VERSION` change in `project.yml`; if the generated diff
    contains any other change, fail instead of merging.
12. Use `gh pr merge --squash --match-head-commit` with the workflow token. Bruce currently has no
    branch rule that requires an administrative bypass. If repository rules later prevent this
    merge, leave the PR open for the user to merge manually; do not add an admin PAT or bypass.
13. Request `contents: write` and `pull-requests: write`; do not request unrelated permissions.
14. Make reruns safe when the App Store submission, release asset, branch, or PR already exists.

The final GitHub release is created before the workflow starts. If submission fails, keep the tag
and release as immutable history, describe the partial failure, and follow the recovery procedure.

### Release operator tooling

Port and adapt Moolah's release scripts so the operator can:

- verify the branch is `main`, the tree is clean, local `main` matches `origin/main`, GitHub CLI
  authentication works, and CI passed for the exact local SHA;
- compute the next RC version from `MARKETING_VERSION` and immutable repository tags;
- compute the final version, latest RC pairing, RC commit, and previous-final notes base;
- create a GitHub prerelease and its tag at the already-verified local SHA;
- create a final GitHub release and tag at the selected RC commit;
- wait for the workflow associated with that tag; and
- report the workflow result and expected release assets.

Add shell tests for first RC, subsequent RC, previous-final handling, final-to-RC pairing, rejection
of older RCs, differing commit SHAs, malformed versions, and tag selection. Creating a raw matching
tag may still trigger GitHub Actions, but the release guide must identify the preflight/create
commands as the supported operator path.

### Repository verification

Codex runs:

```sh
just format
just format-check
just build
just test
just test-release-scripts
bundle exec fastlane lanes
git diff --check
```

Unsigned builds and pure release-script tests must pass without distribution secrets. Signed
lanes are exercised only after Milestones 2 and 3.

### Review gate

- Run `code-review` for scripts, project settings, workflow structure, and scope.
- Run `appstore-review` for bundle identifiers, versioning, icons, privacy declarations,
  entitlements, signing, archive/export settings, and distribution readiness.
- Fix every finding and repeat the affected review until it reports no findings.
- Commit the completed repository change before reporting Milestone 1 complete.

## Milestone 2: Apple account and signing setup

**Owner:** User, with Codex providing exact commands and read-only verification

### Manual Apple Developer setup

1. Confirm the Apple Developer Program membership and team represented by `DEVELOPMENT_TEAM` are
   active.
2. Register or confirm the explicit identifier `net.symphonious.bruce`.
3. Enable Associated Domains for that identifier so the production profile accepts
   `webcredentials:bruce.symphonious.net`.
4. Confirm the public Apple association file contains the same Team ID and bundle identifier.
5. Create or confirm an Apple Distribution certificate and App Store provisioning profile for
   iOS distribution.
6. Create or confirm a Developer ID Application certificate and Developer ID provisioning
   profile for direct Mac distribution.

### Manual App Store Connect setup

1. Create or confirm the Bruce iOS app record for bundle ID `net.symphonious.bruce`.
2. Confirm version `0.1.0` is suitable for the first RC or update `MARKETING_VERSION` through a
   reviewed repository change before tagging.
3. Complete the agreements and minimum TestFlight contact/compliance information required by the
   account.
4. Create or select a **team** App Store Connect API key. Individual API keys cannot perform the
   provisioning and `notarytool` operations required here.
5. Use the least-privilege team-key role that supports build upload, review submission, read-only
   provisioning access, and notarisation. Start with App Manager for CI and verify all four
   operations. If certificate/profile creation requires broader authority, use a separate,
   short-lived local bootstrap credential rather than broadening the persistent CI key.
6. Download and retain its `.p8` key. Apple does not allow downloading the private key again.
7. Configure internal tester groups. Configure external groups and Beta App Review information
   only if external distribution is wanted.

### Manual Match bootstrap

1. Create a dedicated private Match repository for Bruce. Do not point Bruce at Moolah's Match
   repository, even when both apps belong to the same Apple team.
2. Create a Bruce-specific Match encryption password and a least-privilege Git credential scoped
   to the dedicated repository. Do not reuse Moolah's Match password or repository credential.
3. Ensure the operator has writable access to the Bruce Match repository.
4. From a trusted local machine, run the checked-in writable certificate/profile lanes only after
   reviewing the identifiers and Apple team.
5. Confirm the Bruce Match repository now contains the App Store and Developer ID profiles for
   `net.symphonious.bruce` without exposing their contents in logs or commits in Bruce.
6. Return CI to read-only Match operation.

The user may explicitly authorize Codex to execute the bootstrap commands, but that approval must
name the Apple team, bundle identifier, Match repository, and signing types. Without that approval,
Codex provides commands and verifies outcomes only.

### Checkpoint evidence

- The App ID has Associated Domains enabled.
- App Store Connect recognizes the Bruce app record.
- The selected team API key succeeds for build upload, App Review submission, read-only Match
  provisioning access, and a notarisation validation on the intended Apple team.
- Match can retrieve both signing types on a trusted Mac.
- `security find-identity -v -p codesigning` shows the expected Apple Distribution and Developer
  ID Application identities after Match synchronization.

No release tag is created at this checkpoint.

## Milestone 3: GitHub environments and secrets

**Owner:** User for secret values; Codex may create or inspect non-secret environment settings

1. Create GitHub Actions environments `rc-release` and `production-release` in `ajsutton/bruce`.
2. Do not configure required reviewers for either environment. The explicit approval obtained
   before creating a release tag is the authorization gate; tag creation must be sufficient to
   start signing and distribution automatically.
3. Store these secrets in `rc-release`:

   ```text
   ASC_KEY_ID
   ASC_ISSUER_ID
   ASC_KEY_CONTENT
   DEVELOPMENT_TEAM
   MATCH_GIT_URL
   MATCH_PASSWORD
   MATCH_GIT_BASIC_AUTHORIZATION
   ```

4. Store the App Store Connect secrets and `DEVELOPMENT_TEAM` in `production-release`:

   ```text
   ASC_KEY_ID
   ASC_ISSUER_ID
   ASC_KEY_CONTENT
   DEVELOPMENT_TEAM
   ```

5. Store `ASC_KEY_CONTENT` as the base64-encoded `.p8` contents expected by Fastlane.
6. Use the dedicated Bruce Match repository URL, encryption password, and least-privilege
   repository credential. None of these values should reference or unlock Moolah's Match
   repository. When `MATCH_GIT_BASIC_AUTHORIZATION` is used, `MATCH_GIT_URL` must use HTTPS rather
   than SSH (for example, `https://github.com/ajsutton/bruce-match.git`).
7. Do not put these values in `.env`, workflow YAML, release notes, issue comments, or chat.
8. Confirm only the RC workflow references `rc-release` and only the final workflow references
   `production-release`.
9. In GitHub Actions settings, enable **Allow GitHub Actions to create and approve pull requests**.
   Bruce currently has this disabled, and the final workflow's standard `GITHUB_TOKEN` cannot
   create the post-release bump PR until it is enabled.

Codex can verify the environment configuration and secret names through GitHub's API. GitHub does
not reveal secret values, so successful signed validation is the proof that the contents are
correct. Codex also verifies that the repository reports
`can_approve_pull_request_reviews: true` before final-promotion automation is accepted.

## Milestone 4: signed validation without an RC tag

**Owner:** Codex after user authorization; user supplies/installs secret values

1. Run the certificate lanes read-only and confirm the expected profiles are selected.
2. Build and validate the iOS App Store archive without intentionally distributing it to tester
   groups.
3. Build, sign, notarise, staple, and zip the Mac app using an explicit non-placeholder diagnostic
   build number.
4. Extract the zip into a temporary directory and verify:
   - the archive contains exactly one top-level `Bruce.app`;
   - `codesign --verify --deep --strict` succeeds;
   - `spctl` accepts it as a notarised Developer ID app;
   - `stapler validate` succeeds; and
   - version and build metadata match the supplied values.
5. Store command output under `.agent-tmp/`; do not commit archives, profiles, certificates, or
   key material.

If Apple's validation or notarisation service treats a validation upload as externally visible
release state, Codex must show the exact command and obtain approval before running it.

## Milestone 5: first RC

**Owners:** User approval, then Codex execution and monitoring

1. Codex runs `just release-preflight` and records the pinned commit SHA.
2. Codex proposes:
   - marketing version;
   - build-number strategy;
   - RC tag;
   - exact commit SHA;
   - release notes;
   - iOS App Store/TestFlight signing path; and
   - macOS Developer ID/notarised-zip signing path.
3. The user explicitly approves those values and authorizes tag creation and upload.
4. Codex runs `just release-create-rc` with the approved notes.
5. The `rc-release` job starts immediately. Codex verifies the displayed tag and commit while
   monitoring it.
6. Codex monitors `release-rc.yml` to completion.
7. Codex verifies:
   - the workflow used the approved tag and SHA;
   - the TestFlight upload step succeeded;
   - the macOS notarisation and staple steps succeeded;
   - the GitHub release remains marked as a prerelease;
   - `Bruce-<version>.zip` is attached; and
   - the attested manifest binds the tag, commit, build number, and Mac zip digest.
8. Codex reports any App Store Connect processing delay separately from workflow success.

Failures do not justify moving or deleting the RC tag. Fix the cause on `main`, pass review and CI,
then cut the next RC number.

## Milestone 6: user smoke test and acceptance

**Owner:** User, with Codex investigating reported failures

1. Install the TestFlight build on a supported physical iOS device.
2. Confirm launch, Home Assistant discovery, authentication, reconnection, and representative
   controls work in the release build.
3. Download the Mac zip from the GitHub prerelease rather than using the workflow build directory.
4. Extract it, move `Bruce.app` to `/Applications`, and launch it through Finder.
5. Confirm Gatekeeper does not show an unidentified-developer or damaged-app warning.
6. Confirm launch, authentication, Keychain access, local-network discovery, reconnection, and
   representative controls work on macOS.
7. Confirm both apps report the expected marketing version and build number.

The RC pipeline is accepted when the first RC workflow is green, the expected GitHub assets exist,
the iOS build is available to the intended TestFlight testers, and both platform smoke tests pass.

## Milestone 7: final-release readiness

**Owner:** User for App Store Connect state and release approval; Codex for inspection and notes

The latest RC for the marketing version must have completed Milestone 6. Do not promote an older
RC while a newer RC tag exists.

### Manual App Store Connect preparation

The final Fastlane lane deliberately skips metadata and screenshots. Before promotion, the user
must complete and verify the App Store Connect version record, including all fields Apple requires
for this app and account:

- app name, subtitle, description, keywords, category, copyright, and support contact;
- support URL, privacy-policy URL, and marketing URL when used;
- screenshots and other required product-page assets for every supported device class;
- age rating, content-rights declarations, app privacy answers, pricing, availability, and tax or
  banking agreements;
- export-compliance answers consistent with the checked-in app declarations;
- App Review contact details and review notes; and
- a stable review path for Home Assistant-dependent functionality.

Because Bruce requires a Home Assistant connection, Apple reviewers need functional access. The
user must provide a reachable review instance with active temporary credentials and all necessary
setup material, or Bruce must have a fully featured demo mode that exercises the submitted
functionality without external access. Verify the chosen path immediately before submission and
keep it available throughout review. Instructions without functional access are insufficient. Do
not put review credentials in the repository, GitHub release notes, or workflow YAML; store them
only in App Store Connect's review fields.

### Final release notes and approval

1. Codex runs `just release-next-version final` and identifies the latest RC tag, its commit, the
   final version, and the previous final tag used as the notes base.
2. Codex prepares end-user release notes covering the cumulative change since the previous final
   release, not merely the delta from the last RC.
3. Codex confirms App Store Connect has finished processing the selected TestFlight build and no
   conflicting submission is in progress.
4. Codex shows the user:
   - final marketing version and tag;
   - paired RC tag;
   - immutable commit SHA;
   - TestFlight build number;
   - attested manifest identity;
   - Mac zip name and attested digest;
   - final release notes;
   - automatic-release-after-approval behaviour; and
   - proposed next marketing version for the post-release bump.
5. The user explicitly approves final tag creation, App Store review submission, automatic release
   after approval, Mac asset promotion, and the mechanical post-release bump merge.

No final tag is created without that approval.

## Milestone 8: approved final promotion

**Owners:** User approval, then Codex execution and monitoring

1. Codex runs `just release-create-final <version> <rc-tag> <notes-file>`.
2. The command creates the final GitHub release and tag at the paired RC's commit, which starts
   `release-final.yml`.
3. The `production-release` job starts immediately. Codex verifies the final tag, RC pairing,
   commit, build number, and attested Mac digest while monitoring it.
4. The workflow independently verifies the tag-to-RC pairing and RC attestations before changing
   App Store state.
5. The workflow reads the attested RC build number and submits that existing TestFlight build
   for review with automatic release enabled.
6. The workflow copies the attested RC notarised Mac zip to the final GitHub release without
   rebuilding it and verifies its digest is unchanged.
7. Only after submission and asset promotion succeed, the workflow creates a branch from current
   `origin/main` containing the next `MARKETING_VERSION` change.
8. Before opening the PR, the workflow fails unless the commit changes only the expected
   `MARKETING_VERSION` line in `project.yml`.
9. The workflow opens an auditable PR and immediately squash-merges it without waiting for CI or a
   merge queue, as explicitly allowed for this mechanical post-release change.
10. The workflow resolves the merged commit and verifies its diff contains only the approved
    marketing-version change.
11. Codex monitors the workflow and reports the App Store submission, GitHub asset, and bump-merge
   outcomes independently so a partial failure is visible.

Workflow success means the selected build was submitted to Apple with automatic release requested;
it does not wait for App Review to finish.

## Milestone 9: post-release verification

**Owner:** User for App Review communication; Codex for repository and release-state verification

1. Codex confirms the final GitHub release is not marked as a prerelease and points at the RC
   commit.
2. Codex downloads the final Mac zip, compares it with the RC asset, and confirms matching digests.
3. Codex confirms the post-release bump commit reached `main` and `project.yml` contains the
   intended next marketing version.
4. The user monitors App Store Connect for review questions, rejection, approval, and automatic
   public release.
5. After approval, the user confirms the expected version is available on the App Store.
6. The user downloads the public App Store build and final GitHub Mac zip for a short production
   smoke test.

The complete release pipeline is accepted when the final workflow is green, the Mac asset is
unchanged from the tested RC, the bump is merged, and Apple has released the approved iOS build.

## Recovery rules

- **Apple processing delay:** wait for App Store Connect processing; do not rerun the entire build
  merely because Fastlane returned before processing completed.
- **Transient notarisation failure:** inspect the notary log and rerun the failed workflow only
  when retrying is idempotent for that tag and build number.
- **Signing or entitlement failure:** fix profiles or repository configuration, review the fix,
  land it on `main`, and cut a new RC.
- **iOS upload succeeds but Mac build fails:** keep the RC tag and prerelease, document the partial
  failure, fix on `main`, and cut a new RC rather than rebuilding different source under the old
  tag.
- **Mac succeeds but iOS upload fails:** use the same immutable-tag rule; diagnose, fix, and create
  the next RC.
- **Smoke-test failure:** mark the prerelease notes as obsolete and create a new RC after the fix.
- **Final workflow fails before submission:** correct the external metadata or workflow problem and
  rerun the failed workflow. Do not replace the final tag.
- **Final workflow fails after submission:** first verify App Store Connect state. Rerun only the
  idempotent workflow; it must recognize the existing submission and avoid creating a second one.
- **Apple rejects the submitted build:** address the feedback on `main`, use a new marketing
  version, and perform a new RC and final cycle. Do not move the rejected release's final tag.
- **Mac copy fails after App Store submission:** leave the final tag unchanged and rerun the
  idempotent asset-copy step after diagnosing the failure.
- **Post-release bump fails:** the release remains valid. Rerun the idempotent PR step or create and
  merge the same one-line bump PR manually; do not rerun binary submission merely to repair it.
- **Compromised secret:** revoke it at its source, replace the GitHub environment secret, and
  rotate affected Match encryption or repository credentials as appropriate.

## Non-goals

This plan does not add:

- Mac App Store distribution;
- automatic external TestFlight distribution;
- monthly or scheduled RC tags;
- Sparkle or another Mac auto-update framework;
- CloudKit release gates; or
- a second signing system alongside Match.

Those require separate use cases and reviewed plans.
