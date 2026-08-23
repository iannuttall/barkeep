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

## Publish from GitHub

Update `RELEASE_NOTES.md`. Then increase both values in `version.env` and merge
the change to `main`. GitHub Actions will:

- build and test the app;
- sign the app and DMG with Developer ID;
- notarize and staple the DMG;
- sign the update with Sparkle;
- create the GitHub release and tag; and
- commit the new appcast entry to `main`.

The release workflow needs these GitHub Actions secrets:

- `CERTIFICATE_P12_BASE64`
- `CERTIFICATE_PASSWORD`
- `KEYCHAIN_PASSWORD`
- `ASC_PRIVATE_KEY_BASE64`
- `ASC_KEY_ID`
- `ASC_ISSUER_ID`
- `SPARKLE_PRIVATE_KEY`

The repository must be public at `iannuttall/barkeep`. Installed apps read the
update feed from its `main` branch.

The Sparkle public key is pinned in `Info.plist`. Its private key stays in the
login keychain and in the encrypted GitHub secret. Do not change either key
after the first release.
