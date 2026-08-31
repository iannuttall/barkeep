# Troubleshoot Barkeep

Use these checks before you reset settings or report a bug.

## Barkeep cannot find menu bar items

Open **Barkeep Settings**, select **Advanced**, and check the Accessibility status. Select **Set
Up** if access is not allowed. Turn Barkeep on in **System Settings > Privacy & Security >
Accessibility**, then return to Barkeep and select **Refresh**.

Some apps do not expose their status item through macOS Accessibility. Include the app name in a
bug report when one item is missing but other items appear.

## macOS keeps asking for Accessibility access

Use the same installed app path and the same signing identity for each local build. `make install`
uses `~/Applications/Barkeep.app` and prefers a Developer ID certificate. An ad hoc build can look
like a different app after each rebuild.

Remove old Barkeep entries from the Accessibility list before you add the stable signed app again.
Do not move the app after macOS grants access.

## An item does not move to its new section

Barkeep rejects a move when the source frame, target point, or screen is not safe. Before the drag
starts, Barkeep waits until the item shows a stable position on the screen. macOS decides how menu
bar overflow fits around a camera notch. Barkeep saves the new section only when a second
Accessibility scan confirms that macOS completed the move.

macOS keeps some Apple items, for example Clock and Control Center, on the far right side. A
Command-drag cannot move these items past the Barkeep icon. This is a macOS limit.

Use these checks in order.

1. Open all items with Option-click and make sure the item is visible.
2. Select **Refresh** in the Items settings.
3. Try the section menu on the item row instead of drag and drop.
4. Turn on tighter item spacing when the menu bar has no safe space.
5. Move the item by hand with Command-drag when macOS does not complete the move.

Barkeep keeps the old saved section after a failed move.

## Hidden items appear again too soon

Open **Behavior** settings. Increase **Hide delay** or turn off **Hide items again**. Also check
the click, scroll, hover, app-change, and external-display settings. More than one enabled trigger
can change the current reveal state.

## A keyboard shortcut does nothing

Barkeep uses `Command-Backslash` to show or hide items and `Command-Shift-Space` to open search.
Another app can register the same global shortcut first. Quit the other app or remove its shortcut,
then restart Barkeep.

The current version does not include a shortcut editor.

## Tighter spacing does not change the menu bar

Spacing changes take effect after you log out and log in. Turn the setting off before you remove
Barkeep. Barkeep then restores the preference values that it saved before the change.

## Loading a profile does not rearrange every item

Profiles currently load Barkeep's saved rules and settings. They do not post a set of automatic
item moves. Open the Items screen and move any real menu bar items that do not match the profile.

## Check for Updates is missing

The update command appears only when the app bundle contains a valid Sparkle feed URL and public
key. Run Barkeep from a complete app bundle made by `make build` or install a signed release. A raw
Xcode executable does not contain the full release setup.

## Reset local state without deleting it

Quit Barkeep. Move its state file to a backup name.

```sh
mv "$HOME/Library/Application Support/Barkeep/state.json" \
   "$HOME/Library/Application Support/Barkeep/state.backup.json"
```

Open Barkeep again. It creates default state. Move the backup file back only while Barkeep is not
running.

## Send a useful bug report

Open a [GitHub issue](https://github.com/iannuttall/barkeep/issues). Include the following details.

- macOS version and Mac model
- Number and layout of connected displays
- App name for the affected menu bar item
- Barkeep action and the message that appeared
- Whether the move crosses a MacBook camera notch
- Whether the app came from GitHub or a local build

Do not attach `state.json` until you inspect it. It can contain app names and custom profile names.
