<div align="center">

<img src="Sources/Barkeep/AppIcon.icon/Assets/barkeep.svg" width="150" alt="Barkeep">

# Barkeep

**Keep a crowded macOS menu bar under control.**

Barkeep is a native menu bar manager for macOS. It keeps important items visible and puts
everything else one click away.

[Releases](https://github.com/iannuttall/barkeep/releases) ·
[Report a problem](https://github.com/iannuttall/barkeep/issues) · MIT licensed

</div>

---

## Put every item in one clear section

Barkeep splits the menu bar into three sections.

| Section | What Barkeep does |
|---|---|
| **Always visible** | These items stay in the menu bar. |
| **Hidden** | Click the Barkeep icon to show or hide these items. |
| **Always hidden** | Option-click the Barkeep icon when you need these items. |

Open **Arrange Items** to see all three sections together. Drag an item to another section or
use the menu on its row. Barkeep checks the real menu bar after each move. It saves the new
section only when macOS completes the move.

The default Barkeep icon is a small dot. You can choose from eight monochrome symbols.

## Use Barkeep without leaving your current app

- Click the Barkeep icon to show or hide the Hidden section.
- Option-click the icon to show all sections.
- Right-click the icon for search, settings, updates, and other common actions.
- Press `Command-Backslash` to show or hide items.
- Press `Command-Shift-Space` to find and open a menu bar item.

Barkeep can hide items again after a delay. It can also reveal them when you click, scroll, or
hover in the menu bar. Each optional trigger stops when you turn it off.

## Your menu bar data stays on your Mac

Barkeep has no account and sends no analytics. It does not use Screen Recording. It stores its
settings, item rules, and profiles in one local JSON file.

```text
~/Library/Application Support/Barkeep/state.json
```

Accessibility access lets Barkeep list, open, and move menu bar items. Barkeep makes a fresh
scan before a move and posts a Command-drag only after you choose a new section. Launch, wake,
display changes, and timers cannot move an item.

Touch ID or the Mac password can protect every reveal path. Launch at Login is optional and uses
the macOS login item service.

## Install Barkeep

Signed builds will appear on the [GitHub releases page](https://github.com/iannuttall/barkeep/releases).
The first public build has not shipped yet.

Barkeep supports macOS 14 or later. A local build also needs Xcode 16 or later and XcodeGen.

```sh
brew install xcodegen
make check
make install
```

`make install` builds the app, installs it in `~/Applications`, and opens it. A Developer ID
certificate gives local builds a stable identity. Without one, macOS can ask for Accessibility
access again after a rebuild.

## Verify a downloaded build

Public builds use Developer ID signing and Apple notarization. After a release is available you
can check the installed app with these commands.

```sh
codesign --verify --deep --strict --verbose=2 /Applications/Barkeep.app
spctl --assess --type execute --verbose=4 /Applications/Barkeep.app
```

Each release also includes a SHA-256 checksum for its DMG.

```sh
shasum -a 256 ~/Downloads/Barkeep-*.dmg
```

## Build and test the app

```sh
make check       # Generate the Xcode project and run tests
make build       # Build and sign dist/Barkeep.app
make install     # Install to ~/Applications and open the app
make dmg         # Build a drag-install DMG
make release     # Sign, notarize, staple, and prepare a release
```

These are the main source areas.

```text
Sources/Barkeep/App/             app lifecycle and coordination
Sources/Barkeep/StatusBar/       status items and visibility boundaries
Sources/Barkeep/Accessibility/   item scanning and confirmed moves
Sources/Barkeep/System/          hotkeys, triggers, login, spacing, and updates
Sources/Barkeep/UI/              settings, search, and permission views
Tests/BarkeepTests/              unit tests for state and core rules
scripts/                         build, install, DMG, and release commands
```

Read [AGENTS.md](AGENTS.md) before changing the app. The supporting docs cover the
[product rules](docs/PRODUCT.md), [architecture](docs/ARCHITECTURE.md),
[clean-room source audit](docs/AUDIT.md), [common problems](docs/TROUBLESHOOTING.md), and
[release process](docs/RELEASING.md).

## Current limits

The current app includes the three visibility sections, safe item moves, search, reveal triggers,
Touch ID protection, profiles, backups, tighter item spacing, and Sparkle updates.

A second menu bar, custom bar styling, low-battery rules, scripts, and network triggers are not
part of the current app. Profiles save Barkeep's stored rules and settings. Loading a profile does
not move every real menu bar item into place yet.

## Report bugs and request features

Open a [GitHub issue](https://github.com/iannuttall/barkeep/issues) with your macOS version, display
layout, the app that owns the menu bar item, and what Barkeep did. The
[troubleshooting guide](docs/TROUBLESHOOTING.md) lists safe checks for common problems.

Pull request creation is limited to repository collaborators. This keeps changes tied to the menu
bar safety rules and signed release checks.

## License

Barkeep uses the [MIT License](LICENSE).
