# Razer Custom Utilities

Native macOS utility for a Razer BlackWidow V4 X keyboard and a Razer DeathAdder V2 mouse.

The app was built around direct HID inspection and local event taps so the supported devices can expose useful custom controls on macOS:

- BlackWidow V4 X macro keys M1-M6 with assignable actions.
- DeathAdder V2 special buttons, including the two top buttons mapped in Synapse to F15/F16 and the two side buttons.
- Per-button assignments for shortcuts, apps/scripts, folders, system actions, and show/hide app.
- Keyboard key swapper.
- Raw event viewers for the keyboard and mouse.
- Optional CapsLock LED fix for the keyboard.
- Menu bar utility with launch-at-login and launch-minimized options.

## Supported Hardware

This project currently targets:

- Razer BlackWidow V4 X: `vendor-id=0x1532`, `product-id=0x0293`
- Razer DeathAdder V2: `vendor-id=0x1532`, `product-id=0x0084`

Other Razer devices may expose different HID interfaces, reports, usages, or firmware behavior. Treat this project as a working base for adaptation rather than a universal Razer driver.

## Requirements

- macOS with Xcode command line tools installed.
- Swift Package Manager.
- Input Monitoring and Accessibility permissions for the app.
- For public distribution outside your own Mac: an Apple Developer ID certificate and notarization.

## Build

```bash
./script/build_app.sh
```

The build script creates:

```text
dist/Razer Custom Utilities.app
```

Useful options:

```bash
./script/build_app.sh --release
./script/build_app.sh --debug
./script/build_app.sh --no-launch
```

If a local Apple Development signing identity is available, the script signs the helper and app bundle. That is enough for local development, but not for public Gatekeeper distribution.

## Package a DMG

```bash
./script/package_dmg.sh
```

This builds a release app bundle and creates:

```text
dist/Razer Custom Utilities-<version>.dmg
```

For a GitHub Release intended for other users, sign the app with Developer ID and notarize the DMG before publishing.

## DeathAdder Debug Helper

The helper script focuses only on the DeathAdder V2:

```bash
./script/deathadder.sh
./script/deathadder.sh --special
./script/deathadder.sh --list
```

`--raw` is the default mode and shows all visible HID events for the mouse. `--special` prints only the target buttons used by the app.

## Repository Layout

```text
Sources/RazerCustomUtilities/       App executable entry point
Sources/RazerCustomUtilitiesCore/   SwiftUI app, models, HID services, assets
Sources/RazerHIDTool/               Command-line HID/debug helper
script/build_app.sh                 Build/sign/package app bundle
script/package_dmg.sh               Build release DMG
script/deathadder.sh                DeathAdder V2 debug helper
```

## Distribution Notes

The `.app` can be copied to another Mac, but macOS will require users to grant Accessibility/Input Monitoring permissions again. Public release builds should be:

1. Signed with a Developer ID Application certificate.
2. Packaged into a DMG.
3. Notarized with Apple.
4. Uploaded to GitHub Releases together with the source code.

Without Developer ID notarization, other Macs may block the app or show Gatekeeper warnings even if the code is correct.

See [docs/RELEASING.md](docs/RELEASING.md) for the GitHub release and notarization workflow.
