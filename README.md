# Razer Custom Utilities for MacOS Intel

Native macOS Intel utility for a Razer BlackWidow V4 X keyboard and a Razer DeathAdder V2 mouse.

The app was built around direct HID inspection and local event taps so the supported devices can expose useful custom controls on macOS:

- BlackWidow V4 X macro keys M1-M6 with assignable actions.
- DeathAdder V2 special buttons, including the two top buttons mapped to F15/F16 and the two side buttons.
- Per-button assignments for shortcuts, apps/scripts, folders, system actions, and show/hide app.
- Keyboard key swapper/remapper.
- Raw event viewers for the keyboard and mouse.
- Optional CapsLock LED fix for the keyboard.
- Menu bar utility with launch-at-login and launch-minimized options.

## Supported Hardware

This project was done as a personal utility and experimentation for my Razer devices and currently only supports and has been tested on these models:

- Razer BlackWidow V4 X: `vendor-id=0x1532`, `product-id=0x0293`
- Razer DeathAdder V2: `vendor-id=0x1532`, `product-id=0x0084`

I'm quite sure other similar Razer devices may work or the code can be easily adapted to work on your devices. Treat this project as a working base for adaptation rather than a universal Razer driver.

## Requirements

- macOS with Xcode command line tools installed.
- Swift Package Manager.
- Input Monitoring and Accessibility permissions for the app.
- For public distribution outside your own Mac: an Apple Developer ID certificate and notarization.

## Install

Simply download the .dmg file and copy the app to your applications folder.

IMPORTANT USAGE NOTE: ~~The app doesn't natively recognise the mouse top special buttons (the ones located behind the scroll wheel). You need to manually assign those buttons to F15 and F16 using the Synapse software in a compatible Windows or Apple Silicon machine.~~

No longer necessary since version 2.5.0: the app automatically assigns the DeathAdder V2 top buttons to F15/F16 when it starts or when the mouse is connected.

## Custom Build

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


## Repository Layout

```text
Sources/RazerCustomUtilities/       App executable entry point
Sources/RazerCustomUtilitiesCore/   SwiftUI app, models, HID services, assets
Sources/RazerHIDTool/               Command-line HID/debug helper
script/build_app.sh                 Build/sign/package app bundle
script/package_dmg.sh               Build release DMG
script/deathadder.sh                DeathAdder V2 debug helper
```
