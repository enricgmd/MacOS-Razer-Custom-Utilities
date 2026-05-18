# Releasing

This repo is ready to publish as source code. The generated `.app` and `.dmg` are intentionally ignored by git and should be uploaded only as GitHub Release artifacts.

## Local Release Build

```bash
./script/package_dmg.sh
```

Output:

```text
dist/Razer Custom Utilities-<version>.dmg
```

The version comes from `VERSION`.

## GitHub Repository

```bash
git add .
git commit -m "Initial Razer Custom Utilities release"
git branch -M main
git remote add origin git@github.com:<user>/<repo>.git
git push -u origin main
```

Then create a release:

```bash
git tag "v$(cat VERSION)"
git push origin "v$(cat VERSION)"
```

Upload the DMG from `dist/` to the GitHub Release for that tag.

## Public macOS Distribution

For local builds, `script/build_app.sh` signs with the first available `Apple Development` identity. That is useful for development but is not enough for public Gatekeeper distribution.

For a release intended for other Macs, use a `Developer ID Application` certificate and notarize:

```bash
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./script/package_dmg.sh
xcrun notarytool submit "dist/Razer Custom Utilities-$(cat VERSION).dmg" \
  --keychain-profile "<notary-profile>" \
  --wait
xcrun stapler staple "dist/Razer Custom Utilities-$(cat VERSION).dmg"
spctl -a -vv "dist/Razer Custom Utilities.app"
```

Create the notary profile once with:

```bash
xcrun notarytool store-credentials "<notary-profile>" \
  --apple-id "<apple-id>" \
  --team-id "<team-id>" \
  --password "<app-specific-password>"
```

After notarization, test the DMG on a clean macOS account or another Mac. Users will still need to grant Accessibility/Input Monitoring permissions the first time they run the app.
