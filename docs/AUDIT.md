# Barkeep clean-room and safety audit

Audit date: 2026-08-23

## Scope and provenance

This audit records the product and engineering constraints used to build Barkeep.
Public menu bar manager source and permission-flow examples were reviewed at fixed
revisions to understand platform behavior, failure modes, and user expectations.

Barkeep is a clean-room implementation.

- No external source files, assets, names, or code are included.
- Barkeep uses its own Swift implementation and native system frameworks.
- External behavior was treated as research evidence, not as a specification.
- Barkeep's product rules and live tests decide the final behavior.

Barkeep is MIT licensed. Its core menu bar engine has no third-party runtime
dependency. The update framework remains isolated from launch and menu bar behavior.

## Barkeep product rules reviewed

| Area | Barkeep rule |
|---|---|
| Visibility sections | Always visible, Hidden, and Always hidden stay distinct |
| Item arrangement | A direct drag or section-menu action can request one move |
| Move evidence | Use a fresh live frame before moving and confirm with fresh scans |
| Failed moves | Keep the earlier saved rule and restore the earlier reveal state |
| Search | Use the current snapshot and refresh only on request |
| Reveal behavior | Click reveals Hidden; Option-click reveals all items |
| Background work | Launch, wake, display events, timers, and updates never move items |
| Permissions | Accessibility only for listing, opening, and moving menu bar items |
| Saved data | Keep one local, versioned settings document with no saved geometry |
| Updates | Signed updates remain separate from app launch and the menu bar engine |

## Main findings

### Permission setup can stay short

The permission flow can do more than open a Privacy page while remaining narrow.
Barkeep registers the Accessibility request, opens the exact settings page, follows
the System Settings window with a small guide, and provides the signed app as a file
drag source when it is missing from the list.

The drag source publishes only the app file URL. A stable signature is required:
an unsigned or changing build can appear to drag while the system refuses to retain
the permission.

### macOS owns status items and live layout

There is no public API that assigns another process's status item to a Barkeep
section. Barkeep uses its own status items as section boundaries and posts a
user-initiated Command-drag when the user selects a new section.

Saved geometry is never authoritative. Item frames are temporary evidence from the
current scan and must not be written to disk. The move target, source frame, screen
coordinates, and section boundaries must all come from the current open layout.

### Move confirmation is more important than optimistic state

A Settings move follows one controlled sequence:

1. Open all sections.
2. Scan the live menu bar.
3. Match the selected item.
4. Read current boundary frames.
5. Normalize and validate both endpoints.
6. Post one Command-drag.
7. Return the pointer after the drop settles.
8. Scan until the item reappears and its section is confirmed.
9. Save only after confirmation.
10. Restore the earlier reveal state.

The Settings columns must use section assignments captured with the same open
boundary snapshot as their item frames. Reclassifying cached frames against a later
collapsed boundary layout makes counts flap without any real move.

### Recovery must not move the pointer

Old geometry becomes unsafe after wake, display changes, and Space changes.
Automatic repair can fight the user and move the pointer without a direct action.

Barkeep therefore does not post synthetic input during launch, wake, display events,
app events, timers, or update work. It may invalidate stale evidence and explain a
problem, but only a direct item-section action can move one item.

### macOS owns notch overflow

The system already decides which menu bar items fit around a camera housing and
hides overflow when space runs out. A straight cursor path crossing the center of a
notched display does not prove that a move cannot land.

Barkeep does not preemptively reject a Settings move because of an estimated notch
rectangle. Displays without a notch follow the same path. Barkeep validates the
source, target, and current screen, attempts the move, and trusts fresh confirmation
scans instead of guessing from the display shape.

### Idle work must stay near zero

Barkeep does not continuously scan Accessibility data. Settings and search request
fresh scans when needed. Optional reveal triggers own their timers, event monitors,
and observers and stop them when disabled.

### Install and update work stays separate

Update checks cannot block launch, open an unrelated modal window, or delay the menu
bar engine. Release builds must be signed, notarized, and tested from the same archive
that users download.

## Product problems to avoid

- Do not blur the difference between Always visible and Hidden.
- Do not make the user learn modifier-click rules before setup works.
- Do not put normal controls in an Advanced page.
- Do not add a large onboarding flow.
- Do not repair a layout by moving the pointer in the background.
- Do not rebuild status items for every app, Space, or display event.
- Do not classify cached item frames against unrelated boundary geometry.
- Do not report a move as complete before a live scan confirms it.
- Do not guess that a camera housing blocked a move.
- Do not make updates part of app launch.

## Test gates for Barkeep

Automated tests must cover pure state, boundary, target, and coordinate logic.
Release validation must also check real behavior with the signed app because
source-text tests cannot prove that synthetic input moved a status item.

- The app stays hidden and opens no window while idle.
- Always visible items, including protected system items, classify correctly.
- Empty sections accept their first item.
- A direct move changes the real section and stays there.
- A failed move leaves the saved rule unchanged.
- Item order stays stable after relaunch and wake.
- Display changes invalidate temporary geometry.
- Notched and non-notched displays allow normal Settings moves.
- No passive event moves the pointer.
- Authentication protects every reveal path.
- Search opens and closes without keeping a scan timer alive.
- Update failure does not delay app start.
