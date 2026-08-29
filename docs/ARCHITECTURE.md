# Barkeep architecture

Barkeep is one native macOS process. AppKit owns the application lifecycle, status items, panels,
global input, and macOS services. SwiftUI draws the settings, search, and permission views.

## Source map

```text
Sources/Barkeep/App/             lifecycle and AppCoordinator
Sources/Barkeep/Models/          saved and runtime state types
Sources/Barkeep/StatusBar/       three status items and icon rendering
Sources/Barkeep/Accessibility/   permission checks, scans, and item moves
Sources/Barkeep/Permissions/     guided Accessibility setup
Sources/Barkeep/Storage/         versioned local JSON storage
Sources/Barkeep/System/          hotkeys, triggers, login, spacing, and updates
Sources/Barkeep/UI/              settings and search windows
Tests/BarkeepTests/              unit tests
scripts/                         build, install, DMG, and release tools
```

## Runtime components

| Component | Job | Runs outside the main actor? | Can post input? |
|---|---|---:|---:|
| `AppCoordinator` | Connect user actions, state, windows, and services | No | No |
| `StatusBarEngine` | Own the control item and two section boundaries | No | No |
| `AccessibilityScanner` | Read and press current menu bar items | Yes, on one serial queue | Press only |
| `ItemMoveService` | Validate and post one confirmed Command-drag | Yes, on one serial queue | Yes |
| `PermissionAssistant` | Open and follow the Accessibility settings window | No | No |
| `StateStore` | Load and save the versioned JSON document | No | No |
| `TriggerCenter` | Own optional reveal and hide event sources | No | No |
| `HotKeyCenter` | Register the two global keyboard shortcuts | No | No |
| `MenuBarSpacingService` | Apply and restore macOS spacing preferences | No | No |
| `UpdateService` | Keep Sparkle checks separate from core app startup | No | No |

`AppCoordinator` is the only object that joins these parts. Views call coordinator methods. They
do not scan the menu bar or post input themselves.

## Visibility has three states

`StatusBarEngine.State` has three values.

| State | Hidden section | Always hidden section |
|---|---|---|
| `hidden` | Closed | Closed |
| `revealed` | Open | Closed |
| `revealedAll` | Open | Open |

The engine uses two large status item lengths as section boundaries. The control item stays to the
right. macOS keeps each status item's preferred position through its autosave name.

All clicks, hotkeys, triggers, search actions, and menu commands call the coordinator. This gives
authentication and the auto-hide timer one shared path.

## A safe item move has one fixed flow

1. The user selects a new section for one item.
2. The coordinator opens both sections.
3. The scanner reads the live menu bar.
4. The coordinator matches the selected item to the fresh result.
5. The status bar engine gives the target point for the requested section.
6. `ItemMoveService` validates the source frame, target point, and screen.
7. The service posts one Command-drag and returns the pointer to its old position.
8. The scanner reads the live menu bar again.
9. The store saves the rule only when the boundary frames confirm the new section.
10. The coordinator restores the earlier reveal state.

There can be only one move at a time. A failed validation or failed confirmation leaves the saved
rule unchanged.

## Geometry is temporary evidence

A menu bar item frame is valid only for the scan that returned it. Saved state contains no screen
coordinates and no Accessibility objects.

The move service rejects empty or very large source frames. Both endpoints must be on a current
screen. macOS owns menu bar overflow around a camera notch, so Barkeep does not reject a move just
because the cursor path crosses the center of a notched display. The second scan remains the source
of truth for whether the item landed.

## Background work stops when it is not needed

The scanner does not poll. Settings and search ask for a scan when they need current items. The
scanner uses one serial queue because Accessibility calls can block.

`TriggerCenter` creates only the event sources required by enabled settings.

- Hover uses a 10 Hz timer while hover reveal is on.
- Click and scroll use one global event monitor when either action is on.
- App-change hide uses one workspace observer.
- External-display reveal uses one screen observer.

Each settings update stops all old sources before it installs the new set.

## Local state uses one versioned document

`StateStore` writes this file with an atomic replace.

```text
~/Library/Application Support/Barkeep/state.json
```

`BarkeepDocument` contains its format version, settings, item rules, group names, and profiles.
JSON dates use ISO 8601. Import rejects a document with an unknown version.

Menu bar frames and Accessibility elements stay in memory. They are never written to disk.

## Permissions and system changes are narrow

- Accessibility is required to list, open, and move other apps' status items.
- Touch ID or the Mac password is used only when reveal protection is on.
- Launch at Login is optional and uses the main app service.
- Tighter spacing changes two user-level macOS preferences. Barkeep records the old values and
  restores them when the setting is off.
- Screen Recording is not used.
- Network access is limited to the signed Sparkle update feed.

## Releases keep updates outside the core engine

The app target links Sparkle. `UpdateService` creates the updater only when the bundle has a feed
URL and public EdDSA key. Scheduled checks stay quiet until the user opens Barkeep or an update is
ready.

Release builds use Developer ID signing, hardened runtime, Apple notarization, DMG stapling, and a
SHA-256 checksum. The private signing material stays on the release Mac. GitHub receives only the
signed DMG, checksum, public appcast, and release notes.

## Tests cover stable logic and launch safety

The unit target checks boundary classification, product defaults, state persistence, observation,
and icon rendering. CI also builds the app, checks the Sparkle framework, verifies the signature,
and confirms that the process stays open after launch.

Real menu bar moves need a signed app and Accessibility access. Test them manually with the same
app archive that will ship. Source-only tests cannot prove that macOS completed a move.
