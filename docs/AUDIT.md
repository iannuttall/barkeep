# Ice and SaneBar audit

Audit date: 2026-08-23

This audit used these fixed source versions:

- Ice: `11edd39115f3f43a83ae114b5348df6a0e1741cf`
- SaneBar: `478e47908d18bbda7906404e2bd9c615472d92c1`
- Anarlog permission flow: `a0ad6867702220205adf671490325716b803b8a9`

The source was cloned to `/tmp/nice-audit.uDHXp6`. Barkeep does not include files,
assets, names, or code from either project.

## License result

- Ice uses GPL-3.0.
- SaneBar now uses MIT. It changed to MIT in June 2026.
- Barkeep uses MIT.
- Barkeep is a clean-room build, even where SaneBar permits reuse.
- Anarlog uses MIT outside its separate `enterprise` folder. Barkeep studied
  its public permission flow, but uses new Swift code and native SwiftUI.

## Size and dependencies

| Project | Swift source | Main packages | Test result |
|---|---:|---|---|
| Ice | about 18,156 lines | AXSwift, Sparkle, LaunchAtLogin, CompactSlider, Ifrit | No test target was found |
| SaneBar | about 70,217 lines | KeyboardShortcuts, SaneUI, Sparkle, old Setapp code | Many tests exist, but its own audit says some tests only check source text |
| Barkeep target | small by design | No runtime package for core behavior | Unit tests plus live tests |

Barkeep uses Apple frameworks for its core behavior. A later release can use
Sparkle as one small, isolated update module.

## Feature map

| Area | Ice | SaneBar | Barkeep rule |
|---|---|---|---|
| Three visibility sections | Yes | Yes | Make all three clear on the first screen |
| Direct item arrangement | Yes | Yes | Drag or use a clear section menu |
| Search and open an item | Yes | Yes | Fast cached search with keyboard control |
| Panel below the menu bar | Yes | Yes | One compact native panel |
| Full second menu bar | Yes | Yes | Optional, not the default |
| Auto-hide | Yes | Yes | One timer with a visible state |
| Hover, click, and scroll reveal | Yes | Yes | Off by default except click |
| Always visible items | Indirect | Indirect and hard to find | A first-class section and promise |
| Always hidden items | Yes | Yes | A first-class section |
| Item hotkeys | Partial | Yes | Native global hotkeys |
| Profiles | Roadmap | Yes | Save the three lists and related rules |
| Groups | Roadmap | Yes | Optional labels in search, not a new layout system |
| Smart triggers | Roadmap | Yes | Small event modules that can be fully disabled |
| Touch ID lock | No | Yes | Optional LocalAuthentication gate |
| Menu bar style | Yes | Yes | Optional overlay, kept outside the core engine |
| Item spacing | Beta | Yes | Reversible system setting with a clear logout note |
| Import and export | No | Yes | Versioned Barkeep JSON; import is separate code |
| AppleScript | No | Yes | Small command surface with the same auth gate |
| Updates | Sparkle | Sparkle | Signed updates only; no update prompt at launch |

## Main findings

### Permission setup can guide the user in System Settings

Anarlog does more than open a Privacy page. It places a small guide over the
System Settings window and provides its app icon as a file drag source. The
user drags the app into the Accessibility list and turns on the switch.

Barkeep uses this behavior with a small reusable `PermissionAssistant`. It
registers the permission request, opens the exact Accessibility page, follows
the System Settings window, and closes when access is granted. Its drag source
sends only the app file URL because the settings list rejects general URL data
on some macOS versions.

The app must have a valid signature. An unsigned build can appear to drag but
macOS can refuse to add it to the list without an error.

### 1. macOS owns the hard part

Apple does not provide a public API that assigns another app's status item to
a section. Menu bar managers use their own status items as section boundaries.
They use Accessibility and user-style Command-drag events for item moves.

This means an app must treat all saved geometry as a hint. A live status item
frame is the only safe source for a move.

### 2. Recovery code can make the app less reliable

The SaneBar history shows many failures after wake, display changes, and Space
changes. Old geometry caused wrong moves. Automatic repair also moved the
pointer and fought macOS.

Barkeep will not make an automatic synthetic item move during wake, launch, or
idle time. It can detect a problem and offer one Repair action. Only a direct
user action can post a Command-drag event.

### 3. The notch is a real limit

On macOS 26, a synthetic drag can fail when its path crosses the camera notch.
Screen Recording can expose more window data, but it adds a broad permission
and still does not make all moves safe.

Barkeep will start with Accessibility only. It will explain a blocked notch move
and offer search, a second bar, or tighter spacing. It will not claim success
until a live scan confirms the new section.

### 4. macOS 27 is not a safe target yet

Both projects report that the macOS 27 beta changed the menu bar system. Their
current section and move methods can fail. Barkeep targets macOS 14 through 26
until a public and testable macOS 27 path exists.

### 5. Idle work must stay near zero

Ice has reports about WindowServer growth, freezes, and update windows. SaneBar
has reports about memory growth, repeated recovery, and unwanted UI.

Barkeep will not scan menu bar items in a loop. It scans on request and after a
small set of invalidation events. Optional triggers own their timers and stop
them when the feature is off.

### 6. Install and update work must be separate

Both projects have user reports about install or update trouble. Barkeep keeps
the update module outside the menu bar engine. A failed update check cannot
block app start or open a modal window. Release builds must be signed,
notarized, and tested as the same archive that users download.

## Product problems to avoid

- Do not hide the difference between Always visible and Hidden.
- Do not make the user learn modifier-click rules before setup works.
- Do not put normal controls in an Advanced page.
- Do not show a large onboarding flow.
- Do not repair a layout by moving the pointer in the background.
- Do not rebuild status items on every app, Space, or display event.
- Do not use cached pixels after the display layout changes.
- Do not report a move as complete before a live scan confirms it.
- Do not make updates part of app launch.

## Test gates for Barkeep

The release test must check real behavior, not source text:

- The app stays hidden and opens no window while idle.
- Always visible items stay to the right of the Hidden boundary.
- A direct move changes the real section and stays there.
- A failed move leaves the saved rule unchanged.
- Item order stays stable after relaunch and wake.
- A display change invalidates all saved geometry.
- No passive event moves the pointer.
- Touch ID blocks all reveal paths, including automation.
- Search opens and closes without keeping a scan timer alive.
- Update failure does not delay app start.
