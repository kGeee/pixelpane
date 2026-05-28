# Pixel Pane Release Baseline

Last updated: 2026-05-27

Pixel Pane uses Direct distribution for alpha and v1. Releases are signed with Developer ID, notarized by Apple, packaged as a DMG, and delivered through Sparkle once the app embeds the Sparkle framework.

## Signing And Entitlements

Current Xcode target settings:

- App sandbox: disabled (`ENABLE_APP_SANDBOX = NO`)
- Hardened runtime: enabled (`ENABLE_HARDENED_RUNTIME = YES`)
- Info.plist generation: enabled (`GENERATE_INFOPLIST_FILE = YES`)
- Menu-bar-only app: enabled (`INFOPLIST_KEY_LSUIElement = YES`)
- Bundle identifier: `pane.PixelPane`
- Minimum macOS: `15.2`

There is intentionally no checked-in `.entitlements` file in the app target today. Xcode still generates a transient signing entitlement file at build time from target settings. The current Debug build signs with:

- `com.apple.security.files.user-selected.read-only`
- `com.apple.security.get-task-allow` for debugging

The app does not request App Sandbox, ScreenCaptureKit sandbox, app group, network client, or automation entitlements from a checked-in entitlements plist. This matches the Direct distribution decision in `workflow/decisions.md`.

Keep this baseline until a story explicitly needs a new entitlement. If an entitlement is added, document the product reason here and in `workflow/decisions.md` if it changes privacy, distribution, or platform behavior.

## Local Development

Debug builds may keep automatic signing with the development team configured in the Xcode project. Local development should continue to use:

```bash
PixelPane/Scripts/verify-debug-build.sh
```

The wrapper runs the Debug `xcodebuild` verification used by workflow stories.

## Sparkle Update Plan

Pixel Pane's update feed will be an HTTPS Sparkle appcast served from the public release site. The planned production URL is:

```text
https://pixelpane.app/appcast.xml
```

Until the custom domain is live, beta builds may use a temporary HTTPS URL under the release-site host, for example:

```text
https://snehithnayak.github.io/pixel-pane/appcast.xml
```

The app should embed only one appcast URL per release channel. The first beta can use a single `beta` channel; a separate stable channel can be introduced later with a second appcast once external beta and public releases need different cadences.

Sparkle integration requirements before the first update-enabled beta:

- Add Sparkle to the Xcode project through Swift Package Manager or the official framework distribution.
- Set `SUFeedURL` in app metadata to the chosen appcast URL.
- Set the Sparkle public EdDSA key in app metadata after generating the keypair.
- Keep `CFBundleShortVersionString` and `CFBundleVersion` incrementing for every shipped build.
- Verify that a clean install can discover and install a newer signed/notarized build from the appcast.

## Sparkle EdDSA Key Handling

Sparkle EdDSA keys are release secrets. They must not be committed to git, embedded in documentation, stored in app source, or copied into issue/chat history.

Key handling rules:

- Generate the Sparkle EdDSA keypair on a trusted release machine with Sparkle's `generate_keys` tool.
- Store the private key in a user-owned password manager or release keychain entry with restricted access.
- Store the public key in the app metadata only.
- Use the private key only during release packaging/appcast generation.
- Rotate the key if the private key is exposed, if a release machine is compromised, or if release ownership changes.

The private key belongs with other release-only secrets such as Developer ID credentials and notarization credentials. It is not a backend secret and should not be deployed to Cloudflare.

## Manual Developer ID Release Checklist

Prerequisites:

- Apple Developer Program membership.
- Developer ID Application certificate installed in the release keychain.
- App Store Connect API key or Apple ID credentials available to `notarytool`.
- A clean working tree and an agreed release version/build number.
- Sparkle EdDSA private key available from the release secret store.
- Sparkle appcast destination prepared and writable.
- Release notes prepared for the appcast item.

Build and archive:

```bash
xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Release clean archive -archivePath build/PixelPane.xcarchive
```

Export or copy the archived app, then sign with the Developer ID Application identity if the archive/export did not already produce the final signature. Confirm the app bundle version and short version match the release notes before packaging.

```bash
codesign --force --options runtime --timestamp --sign "Developer ID Application: <Team Name> (<Team ID>)" "build/PixelPane.app"
```

Verify signing and hardened runtime:

```bash
codesign --verify --deep --strict --verbose=2 "build/PixelPane.app"
codesign -dvv "build/PixelPane.app"
spctl --assess --type execute --verbose=4 "build/PixelPane.app"
```

Create the DMG with the chosen packaging tool. The exact DMG layout/tooling can be refined in the beta readiness story, but the output must contain only the signed app and install affordances.

Submit and staple notarization:

```bash
xcrun notarytool submit "build/PixelPane.dmg" --keychain-profile "<notarytool-profile>" --wait
xcrun stapler staple "build/PixelPane.dmg"
xcrun stapler validate "build/PixelPane.dmg"
spctl --assess --type open --verbose=4 "build/PixelPane.dmg"
```

Generate or update the Sparkle appcast after the notarized DMG is final. The appcast item must point to the released DMG, include the correct version/build numbers, include release notes, and include Sparkle's EdDSA signature for the archive. Use Sparkle's appcast-generation tooling rather than hand-editing signatures.

Before publishing the appcast:

- Confirm the DMG URL is HTTPS and publicly reachable.
- Confirm the enclosure length and EdDSA signature match the final notarized DMG.
- Confirm the appcast URL validates with Sparkle tooling.
- Keep a copy of the final DMG, appcast, release notes, and notarization log in the release archive.

Final manual QA:

- Install the stapled DMG on a clean macOS machine.
- Confirm Gatekeeper opens the app without an unidentified-developer warning.
- Confirm the app has no Dock icon and appears in the menu bar/notch flow.
- Confirm Screen Recording permission recovery works from the fresh install.
- Confirm hover-open notch chat focuses the composer.
- Confirm chat routes through Agent Kernel V2.
- Confirm selected-region capture and OCR can seed Agent Kernel V2 context without persisting image pixels.
- Confirm Local Mode is default and Cloud Mode is explicit opt-in.
- Confirm granted file/folder context is unavailable until the user grants it.
- Confirm file writes are staged for approval and risky terminal/process operations require approval.
- Confirm cancellation does not create a fake user turn.
- Confirm dev assistant scripts are not present.
- For update-enabled builds, install the previous beta, publish a newer appcast entry, and confirm Sparkle discovers, downloads, verifies, installs, and relaunches into the new version.
- Record the tested version/build and any release notes in the workflow handoff.
