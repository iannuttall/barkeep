# Release Barkeep

Barkeep uses a local signing workflow. Public builds use Developer ID signing, hardened runtime,
Apple notarization, DMG stapling, and Sparkle EdDSA signatures. GitHub checks the staged files and
publishes the release after the signed appcast reaches `main`.

## Prepare the release Mac

The release Mac needs the following tools and credentials.

- Xcode and its command-line tools
- XcodeGen
- GitHub CLI with access to `iannuttall/barkeep`
- A Developer ID Application certificate for the configured team
- A working `notarytool` Keychain profile, named `portmanager` by default
- The Sparkle private key in the login Keychain, or its path in `SPARKLE_PRIVATE_KEY_PATH`

Apple and Sparkle private keys must stay off GitHub. Do not put them in `release.env`, shell output,
the repository, or a GitHub Actions secret for this workflow.

## Test a local install

Run the full test target first.

```sh
make check
```

Then build and install the signed app.

```sh
make install
```

The app goes to `~/Applications/Barkeep.app`. Keep the path and signing identity stable while you
test Accessibility behavior. A changed identity can make macOS treat the app as a new program.

The build script signs each Sparkle helper before it signs the framework and main app. It rejects a
public build when a component has no Developer ID signature or secure timestamp. It also rejects
the debug `get-task-allow` entitlement before the app reaches Apple.

Check each real behavior before a public build.

- The app launches with no window and stays in the menu bar.
- Accessibility setup opens the correct System Settings page.
- One item can move into each section and stays there after relaunch.
- A failed move does not change the saved section.
- Click, Option-click, both hotkeys, search, and Touch ID work.
- Tighter spacing restores the earlier macOS values when turned off.
- A failed update check does not delay app launch.

## Set the version and release notes

Edit `version.env` and increase both values.

```text
MARKETING_VERSION=0.1.0
BUILD_NUMBER=1
```

`MARKETING_VERSION` uses three-part semantic versioning. `BUILD_NUMBER` is an integer and must
increase for every shipped build.

Update `RELEASE_NOTES.md` with user-visible changes. Commit both files before publishing. The
publish command requires a clean worktree.

## Build a notarized release without publishing it

```sh
make release
```

The command completes these steps.

1. Builds and signs `dist/Barkeep.app`.
2. Checks the signature and hardened runtime.
3. Launches the signed app as a smoke test.
4. Builds and signs `dist/Barkeep-<version>.dmg`.
5. Sends the DMG to Apple for notarization.
6. Staples and checks the notarization ticket.
7. Creates the SHA-256 checksum.
8. Signs the Sparkle update and updates `appcast.xml`.
9. Writes local artifact paths to ignored `release.env`.

Use this command when you want to inspect the final files before GitHub receives them. It changes
`appcast.xml`, so restore or commit that file before another publish attempt.

## Publish the release

Make sure `main` is current, all release changes are committed, and the worktree is clean. Then
run the publish command.

```sh
make publish
```

The command repeats the signed release build, creates a draft GitHub release, commits the new
appcast, and pushes `main`. The `Publish Sparkle release` workflow checks the DMG name, byte size,
checksum, version, build number, download URL, and Sparkle signature. It publishes the draft only
after those checks pass.

Watch the GitHub workflow while it validates the release.

```sh
gh run list --workflow "Publish Sparkle release"
gh run watch
```

## Verify the public release

Download the DMG and checksum from GitHub. Check them as a user would.

```sh
shasum -a 256 -c Barkeep-<version>.dmg.sha256
hdiutil attach Barkeep-<version>.dmg
codesign --verify --deep --strict --verbose=2 /Volumes/Barkeep/Barkeep.app
spctl --assess --type execute --verbose=4 /Volumes/Barkeep/Barkeep.app
```

Install the app and use **Check for Updates** against the public appcast. Do this live update test
before you call the first release complete.

## Recover from a failed publish

The GitHub release stays as a draft when validation fails. Keep it private while you fix the file,
checksum, appcast, or notes. Do not replace a published asset under the same version. Increase the
build number, and increase the public version when users could already have the bad build.

The Sparkle public key is pinned in `Info.plist`. Do not rotate it after the first release without a
migration plan.
