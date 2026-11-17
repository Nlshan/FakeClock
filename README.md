# FakeClock - iOS 26 Inspired Vault App

A reimagining of the iOS Clock application with a built-in, authenticated Instagram web browser.

## Architecture
- **Authenticated Shell**: Access to the app is gated by a custom Keychain-backed timer-duration secret.
- **Instagram Integration**: Features a true `WKWebView` instance, protected by the same security gate.
- **Native Experience**: Rebuilds the Clock's World Clock, Alarm, Stopwatch, and Timer tabs using pure SwiftUI and local notification scheduling.

## Building
The IPA is produced by GitHub Actions, not locally:

1. Push this repository to GitHub (branch `main`).
2. `.github/workflows/build.yaml` runs on a macOS-14 runner: `xcodebuild` builds the `FakeClock` scheme (Release, generic iOS device), the workflow assembles `Payload/FakeClock.app` into `FakeClock.ipa`, validates it (zip listing, plist lint, bundle id, executable), and uploads it as the **FakeClock-IPA** artifact.
3. Download the IPA from the run's Artifacts page.

To regenerate the Xcode project after adding/renaming source files, run:

```
python3 generate_project.py
```

(The generator emits deterministic 24-hex PBX object IDs; output is byte-identical across runs.)

## Limitations
- **Build Environment**: Requires Xcode 15+ on a macOS runner. It cannot be built on Windows — this repo ships the complete `project.pbxproj` plus shared scheme so CI builds without XcodeGen.
- **Signing**: CI output is ad-hoc/unsigned. Installing on a device requires re-signing with your own provisioning (AltStore, Sideloadly, or Xcode on a Mac).
- **Notifications**: Local notifications are best-effort (subject to iOS system resource constraints).
- **Audio**: Uses `AudioToolbox` system tones to avoid bundling audio assets.

## Security
- **No Hardcoding**: The authentication secret is stored exclusively in the Keychain using `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- **Biometric Security**: Biometric unlock triggers a secure session rather than overwriting or replacing the primary credential.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>
