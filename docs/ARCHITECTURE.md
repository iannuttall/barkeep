# Architecture

Barkeep is one native macOS process. The core uses AppKit and Apple system
frameworks. SwiftUI draws small settings and search views.

## Components

| Component | Job | Can post input? | Can run when off? |
|---|---|---:|---:|
| `AppCoordinator` | Connect user actions to services | No | Yes |
| `StatusBarEngine` | Own the dot and two section boundaries | No | Yes |
| `AccessibilityScanner` | Read current menu bar items on request | No | No |
| `PermissionAssistant` | Guide drag-and-switch setup in System Settings | No | No |
| `ItemMoveService` | Move one item after direct user action | Yes | No |
| `ItemStore` | Save rules, groups, profiles, and settings | No | Yes |
| `SearchPanel` | Search cached item snapshots | No | No |
| `TriggerCenter` | Run enabled reveal rules | No | No |
| `AppearanceOverlay` | Draw an optional menu bar style | No | No |
| `UpdateService` | Run quiet Sparkle checks and install a signed release | No | No |

## Core state

The visibility state has only three values:

- `hidden`: Hidden and Always hidden are closed.
- `revealed`: Hidden is open. Always hidden stays closed.
- `revealedAll`: Both sections are open.

Only `StatusBarEngine` changes this state. All clicks, hotkeys, triggers, and
automation call the same coordinator methods.

## Item moves

An item move uses this fixed flow:

1. The user selects a new section.
2. Barkeep opens both sections.
3. Barkeep makes a fresh Accessibility scan.
4. Barkeep checks the source and boundary frames against the current screen.
5. Barkeep posts one Command-drag event.
6. Barkeep makes another fresh scan.
7. Barkeep saves the rule only when the item is in the new section.
8. Barkeep restores the prior reveal state.

No launch, wake, display, Space, or timer event can call the move service.

## Geometry rules

- A frame must sit inside one current screen's menu bar band.
- Cached frames include a display fingerprint and a short expiry time.
- A display change deletes all cached frames.
- Estimated frames can help the UI, but cannot authorize a move.
- A move has a rate limit and one active operation at a time.
- A notch-crossing path is rejected before input is posted.

## Performance rules

- No continuous Accessibility scan.
- No screen capture for core behavior.
- No polling when all related triggers are off.
- Hover uses a low-rate pointer check only while enabled.
- Search reads an in-memory snapshot, then refreshes once in the background.
- Appearance creates one overlay per active menu bar screen only while enabled.
- All observers and timers have clear owners and explicit stop methods.

Initial release budgets on an idle Apple Silicon Mac:

- CPU: below 0.2 percent after launch settles
- Memory: below 45 MB
- Wakeups: below 2 per second with optional triggers off
- Dot click response: below 16 ms for the local state change
- Search window: visible below 100 ms with cached items

## Storage

Barkeep saves one versioned JSON document in:

`~/Library/Application Support/Barkeep/state.json`

It contains settings, item rules, groups, and profiles. It does not contain
Accessibility objects or geometry. Writes use an atomic file replace.

## Permissions

- Accessibility: required to list, open, and move other apps' menu bar items.
  Barkeep registers the request, opens the exact page, and shows a temporary
  guide. The signed app tile is a drag fallback when Barkeep is missing.
- Touch ID: used only when the user enables the reveal lock.
- Launch at Login: optional and managed by `SMAppService`.
- Screen Recording: not used by the first release.
- Network: used only for signed update checks when enabled.

## Release shape

- One app target
- One unit test target
- No helper process for the core app
- Hardened Runtime
- Developer ID signature and notarization
- Update failures cannot block the menu bar engine or app startup
- MIT license
