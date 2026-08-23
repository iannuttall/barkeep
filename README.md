# Barkeep

Barkeep is a fast, native menu bar manager for macOS.

The main rule is simple. Each menu bar item belongs to one of three sections:

- **Always visible**: Barkeep never hides it.
- **Hidden**: Click the Barkeep icon to show or hide it.
- **Always hidden**: Barkeep shows it only when you ask.

The default Barkeep icon is a small dot. You can choose another built-in symbol.

## What works now

This is a clean-room implementation. The first native core now includes:

- Three clear visibility sections
- Click and Option-click reveal states
- Eight native menu bar icons
- Accessibility item scanning and confirmed item moves
- Native search and global hotkeys
- Profiles, import, export, launch at login, and spacing controls
- Developer ID builds and quiet Sparkle updates
- A guided Accessibility setup inside System Settings

The second bar, smart triggers, custom styling, and automation still need work.
The first public GitHub release also needs a live update test. The [source audit](docs/AUDIT.md),
[product rules](docs/PRODUCT.md), and [architecture](docs/ARCHITECTURE.md) define
the full target.

## Build

Requirements:

- macOS 14 or later
- Xcode 16 or later
- XcodeGen

Run the tests:

```sh
make check
```

Build, sign, install, and open Barkeep:

```sh
make install
```

The install command uses the Developer ID certificate and writes the app to
`~/Applications/Barkeep.app`. This stable identity keeps Accessibility access
after rebuilds.

The [release guide](docs/RELEASING.md) covers the notarized DMG, GitHub release,
and Sparkle feed. A public release takes one command after its notes are ready.

## License

Barkeep uses the [MIT License](LICENSE).
