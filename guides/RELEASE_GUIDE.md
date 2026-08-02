# Release Guide

This is the source of truth for Bruce release execution. `justfile` defines each command; this
guide defines their order and approval boundaries.

## Conventions

- RC: `v<MAJOR>.<MINOR>.<PATCH>-rc.<N>`.
- Final: `v<MAJOR>.<MINOR>.<PATCH>`.
- Tags are immutable and are never deleted after they are pushed.
- A final tag points at the same commit as the latest tested RC for that version.
- iOS and macOS use the same marketing version and build number.
- iOS ships through TestFlight and the App Store.
- macOS ships as a directly distributed, Developer ID signed and notarised GitHub release zip.
- Final promotion reuses the tested TestFlight build and Mac zip; it does not rebuild them.

## One-time prerequisites

The manual setup instructions in `plans/RELEASE_AUTOMATION_PLAN.md` must be complete:

- Ruby 3.3 and the Bundler version locked in `Gemfile.lock` are available locally.
- Apple identifier `net.symphonious.bruce` exists with Associated Domains enabled.
- The App Store Connect Bruce record exists.
- A team App Store Connect API key has been validated for upload, review submission, Match, and
  notarisation.
- A dedicated private Bruce Match repository contains App Store and Developer ID signing material
  for `net.symphonious.bruce`. Bruce must not use Moolah's Match repository, encryption password,
  or repository credential.
- GitHub environments `rc-release` and `production-release` exist for release-secret scoping and
  do not require deployment approval.
- The environment secrets listed in the plan exist.
- GitHub Actions is allowed to create pull requests.

CI uses Match read-only. Creating or repairing signing material is a separate, explicitly approved
operator action.

## Release safety boundary

Before creating either release tag, show the user and obtain explicit approval for:

- version and tag;
- exact commit SHA;
- release notes;
- paired RC tag for a final release;
- TestFlight build number and attested Mac zip digest when promoting final;
- iOS signing and distribution path;
- Mac signing and distribution path;
- App Store automatic release after approval; and
- proposed post-release marketing-version bump.

Creating the approved tag is the release authorization. The GitHub environments scope secrets but
must not add a second deployment-approval gate.

## Cut an RC

1. Run:

   ```sh
   just release-preflight
   ```

   It requires clean local `main`, exact synchronization with `origin/main`, authenticated `gh`,
   and successful CI for the pinned SHA. Do not fetch or pull between preflight and tag creation.

2. Inspect all intended changes since the prior release or RC. Confirm every intended PR is
   present before continuing.

3. Run:

   ```sh
   just release-next-version rc
   ```

   Confirm `MARKETING_VERSION` in `project.yml` when the output requests it. A version change must
   land through a normal reviewed commit before restarting preflight.

4. Write concise tester-facing notes describing the change since `notes_base`. Save them under
   `.agent-tmp/release-notes-<version>.md`.

5. Show the release proposal and obtain explicit approval.

6. Create the GitHub prerelease and tag:

   ```sh
   just release-create-rc <version> .agent-tmp/release-notes-<version>.md
   ```

7. Open the Actions run and verify its tag and commit.

8. Wait and inspect status:

   ```sh
   just release-wait v<version>
   just release-status v<version>
   ```

9. Confirm the prerelease contains:

   - `Bruce-<marketing-version>.zip`;
   - `build-number.txt`; and
   - `release-manifest.json`.

10. Verify the manifest and Mac zip attestations with `gh attestation verify`, scoped to
    `ajsutton/bruce` and `.github/workflows/release-rc.yml`.

11. Wait for App Store Connect processing, then smoke-test the TestFlight build on a physical iOS
    device. Install the latest published Mac release, including prereleases, with:

    ```sh
    just install-release-mac
    ```

    Launch `/Applications/Bruce.app` through Finder and smoke-test it. Do not smoke-test a local
    workflow output.

If an RC fails, fix the problem on `main` and cut the next RC number. Never move or delete the bad
tag and never replace its attested assets.

## Promote an RC to final

1. Confirm the latest RC for the current marketing version completed both platform smoke tests.

2. Complete all App Store metadata, privacy, pricing, screenshots, review contact details, and
   review access described in the implementation plan. A reachable Home Assistant review instance
   with active temporary credentials or a fully featured demo mode must remain available throughout
   App Review.

3. Run:

   ```sh
   just release-preflight
   just release-next-version final
   ```

4. Write cumulative end-user notes since the previous final release and save them under
   `.agent-tmp/release-notes-<version>.md`.

5. Download the paired RC manifest and artifacts. Verify the attestations and show the user the
   final tag, RC tag, commit, build number, Mac digest, notes, automatic-release behaviour, and
   next proposed marketing version. Obtain explicit approval.

6. Create the final GitHub release and tag at the RC commit:

   ```sh
   just release-create-final <version> <rc-tag> .agent-tmp/release-notes-<version>.md
   ```

7. Open the Actions run and verify the displayed pairing and attested values.

8. Wait and inspect status:

   ```sh
   just release-wait v<version>
   just release-status v<version>
   ```

9. Confirm:

   - the existing TestFlight build was submitted for review with automatic release enabled;
   - the final GitHub release contains a byte-identical copy of the tested RC Mac zip; and
   - the workflow's one-line post-release version-bump PR was squash-merged.

10. Monitor App Store review. Workflow success means submission succeeded, not that Apple has
    approved or released the build.

## Recovery

- Processing delay: wait; do not rebuild.
- RC signing, upload, notarisation, or smoke-test failure: fix `main` and cut a new RC.
- Final metadata failure before submission: correct App Store Connect and rerun the failed job.
- Final rerun after submission: inspect App Store Connect first. The workflow must not create a
  second submission.
- Final Mac-copy failure: keep the tag, diagnose, and rerun the idempotent copy.
- Post-release bump failure: repair or manually merge the one-line PR; do not resubmit binaries.
- App Review rejection: fix `main`, choose a new marketing version, and run a fresh RC/final cycle.
- Compromised credential: revoke and rotate it at the source before rerunning anything.
