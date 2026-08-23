# Release Barkeep

Barkeep uses the same release account and local tools as Natter and Portman.
Public builds use Developer ID signing, hardened runtime, notarization, a stapled
DMG, and Sparkle update signatures.

## Local install

Run:

```sh
make install
```

The script finds the Developer ID certificate, builds Barkeep, verifies the
signature, installs the app in `~/Applications`, and opens it. This stable path
and signature stop Accessibility access from changing after each build.

## Build a release

Set one semantic version and one increasing build number:

```sh
VERSION=0.1.0 BUILD_NUMBER=1 make release
```

The release command builds, signs, launches, creates the DMG, notarizes, staples,
checks Gatekeeper, signs the Sparkle update, updates `appcast.xml`, and writes a
SHA-256 file.

## Publish a release

Update `RELEASE_NOTES.md`. Increase both values in `version.env`, commit the
change, and make sure `main` is clean and current. Then run:

```sh
make publish
```

The local command uses the shared Developer ID certificate, the `portmanager`
notarization profile, and the Sparkle key in the login Keychain. It builds,
signs, notarizes, staples, and verifies the app. It then creates a draft GitHub
release and pushes the signed appcast.

GitHub checks the DMG size and checksum. It publishes the draft only after the
appcast reaches `main`. GitHub does not store Apple or Sparkle private keys.

The repository must be public at `iannuttall/barkeep`. Installed apps read the
update feed from its `main` branch.

The Sparkle public key is pinned in `Info.plist`. Its private key stays in the
login Keychain. Do not change either key after the first release.
