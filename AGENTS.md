# Agent notes

Barkeep is a local native macOS menu bar manager. It uses Swift 6, an AppKit lifecycle and status
bar, SwiftUI views, XcodeGen, and Sparkle.

## Product rules

- Every item belongs to **Always visible**, **Hidden**, or **Always hidden**.
- Click reveals Hidden. Option-click reveals all items. Right-click opens the command menu.
- `Command-Backslash` toggles items. `Command-Shift-Space` opens search.
- Only a direct item-section action can post a Command-drag.
- A move must use fresh Accessibility data and must pass a second scan before state is saved.
- Launch, wake, display events, app events, timers, and updates must never move an item.
- Touch ID or Mac password protection applies to all reveal paths, including search and triggers.
- Barkeep uses no account, telemetry, cloud sync, or Screen Recording.
- Saved settings, rules, and profiles stay under Application Support.
- Update failure cannot block app launch or the menu bar engine.

Read `docs/PRODUCT.md` before you change visible behavior. Keep `README.md` and
`docs/TROUBLESHOOTING.md` accurate when a user-facing feature changes.

## Repo map

```text
Sources/Barkeep/App/             app lifecycle and coordination
Sources/Barkeep/Models/          settings, rules, profiles, and runtime types
Sources/Barkeep/StatusBar/       visibility boundaries and menu bar icons
Sources/Barkeep/Accessibility/   scans, permission checks, and confirmed moves
Sources/Barkeep/Permissions/     guided Accessibility setup
Sources/Barkeep/Storage/         local versioned JSON state
Sources/Barkeep/System/          hotkeys, triggers, login, spacing, and updates
Sources/Barkeep/UI/              settings and search windows
Tests/BarkeepTests/              unit tests
scripts/                         build, install, DMG, and release entry points
.github/workflows/               public CI and release validation
```

## Commands

```sh
make check
make build
make install
make dmg
make release
make publish
```

`make check` runs XcodeGen before `xcodebuild test`. Generated `Barkeep.xcodeproj`, `.xcode-build`,
and `dist` files are ignored. Do not commit them.

## App structure

`AppCoordinator` is the integration point. It owns the status bar engine, scanner, mover, triggers,
hotkeys, windows, and state store. Views call coordinator methods and observe coordinator or store
state. Do not let views post input or make raw Accessibility calls.

Most app code is isolated to `@MainActor`. `AccessibilityScanner` and `ItemMoveService` each use one
private serial queue for blocking Accessibility or Core Graphics work. Keep shared mutable state on
its existing actor or queue.

`StatusBarEngine` owns exactly three status items.

1. The Barkeep control item
2. The Hidden boundary
3. The Always hidden boundary

All reveal actions must go through `AppCoordinator.requestReveal(all:)`. This keeps authentication
and auto-hide behavior consistent.

## Accessibility and move safety

Treat item frames as temporary evidence. Never save geometry or `AXUIElement` objects to disk.

Keep the item move sequence in this order.

1. Open all sections.
2. Scan the live menu bar.
3. Match the selected item.
4. Read current boundary frames.
5. Validate both endpoints and the notch path.
6. Post one Command-drag.
7. Return the pointer to its earlier position.
8. Scan again.
9. Save only after the new section is confirmed.
10. Restore the earlier reveal state.

There can be only one active move. A failure must keep the earlier saved rule and show a useful
message. Do not add background repair or pointer movement.

The permission helper opens the exact Accessibility page, follows the System Settings window, and
offers the signed app as a file drag source. Keep its pasteboard payload narrow. Do not add a broad
permission to work around one move failure.

## State and settings

`StateStore` writes one versioned JSON document with an atomic replace.

```text
~/Library/Application Support/Barkeep/state.json
```

Import must reject unknown document versions. New saved fields need safe defaults so old documents
continue to decode. Add a migration before you change the meaning of existing fields.

Spacing changes write the `NSStatusItemSpacing` and `NSStatusItemSelectionPadding` preferences.
Always preserve the old values and restore them when the feature is turned off.

Profiles and imports currently load stored rules and settings only. They do not move every live item.
Do not describe them as automatic layout restoration or add automatic moves without a new product
decision and a confirmed, user-controlled flow.

## Trigger lifecycle

`TriggerCenter.update(settings:)` stops existing timers, monitors, and observers before it creates
the required set. Any new optional trigger must follow the same ownership rule.

Idle work must stay near zero. Do not add a continuous Accessibility scan. Search can use its
current snapshot and request one refresh.

## Current feature boundary

The data model contains fields for planned work. The current UI does not provide a second menu bar,
custom menu bar styling, low-battery reveal, group editing, network triggers, script triggers,
automation, or editable hotkeys. Do not claim these features in public docs until the working UI and
tests exist.

## Testing

Add unit tests for pure state and geometry changes. Run `make check` for every source or project
change. A docs-only change can use focused link, style, and diff checks.

CI must continue to complete these checks.

- Generate the Xcode project
- Run unit tests with code signing off
- Build the complete app bundle
- Check that Sparkle is present
- Verify the app signature
- Launch the app and confirm that it stays running

Synthetic item moves need a signed local app and macOS Accessibility access. Test them with the same
archive that will ship. A source-text test does not prove that a real move worked.

## Release shape

- macOS 14 or later
- One app target and one unit test target
- Developer ID signing and hardened runtime
- Apple notarization and DMG stapling
- Sparkle feed with a pinned EdDSA public key
- SHA-256 checksum with every public DMG

`scripts/build-app.sh` must sign Sparkle's XPC services, updater app, autoupdate tool, framework,
and main app in that order. Every public component needs a Developer ID signature and secure
timestamp. The main app must not contain `com.apple.security.get-task-allow`. Do not rely on
Xcode's outer app signature because Sparkle's downloaded helper tools use ad hoc signatures.

`scripts/release.sh` uses local Apple and Sparkle credentials. Never commit signing identities,
notary credentials, private keys, `release.env`, or release artifacts.

Update `version.env` and `RELEASE_NOTES.md` before a public release. `make publish` requires a clean
worktree, creates a draft GitHub release, commits the signed appcast, and pushes it. GitHub publishes
the draft only after the release workflow validates the assets and checksum.

The Sparkle public key and feed URL are pinned in `Info.plist`. Do not rotate the key or change the
feed after the first release without a migration plan.

GitHub issues are open. Pull request creation is limited to repository collaborators.
