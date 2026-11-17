# Build Progress — FakeClock

Updated: 2026-11-16

## Completed stages

| Stage | Status | Evidence |
|---|---|---|
| 1. Inspect files | DONE | 48 Swift sources, Info.plist, Assets.xcassets present |
| 2. Check tools | DONE | Windows host: `python3` 3.14 + Swift 6.4 toolchain only. **No xcodegen, no xcodebuild** (xcodebuild is macOS-only) |
| 3. Configuration | DONE | exportOptions.plist (development/automatic signing), Info.plist fixed (`armv7`→`arm64`, literal `APPL` package type) |
| 4. Generate project | DONE | `generate_project.py` executed → complete `project.pbxproj` |
| 5. Validate project | DONE | Independent Python pass: brace balance, all 10 PBX/XC sections, 143 object IDs all exactly 24 uppercase hex, zero duplicates, every referenced ID defined, all 48 files in Sources phase, Assets in Resources phase. Rerun byte-identical (SHA-256 `692b2664…`) |
| 6. Compile | BLOCKED (env) | Cannot run on Windows. Delegated to GitHub Actions macOS runner via `.github/workflows/build.yaml` |
| 7–10. Fix errors / Archive / Export IPA / Verify IPA | PENDING CI | build.yaml performs build → assemble Payload/*.app → zip → unzip-validate (Info.plist lint, bundle id, executable presence) → upload artifact |

## Files created / modified this stage

- `generate_project.py` — replaced stub with working deterministic generator (SHA-256 seeded 24-hex IDs)
- `FakeClock.xcodeproj/project.pbxproj` — regenerated complete (738 lines): PBXBuildFile ×49, PBXFileReference ×51, nested PBXGroups mirroring the directory tree, Sources/Frameworks/Resources phases, PBXProject + PBXNativeTarget, Debug/Release XCBuildConfigurations (deployment target 16.3, bundle id com.fake.clock, automatic signing), XCConfigurationLists
- `FakeClock.xcodeproj/xcshareddata/xcschemes/FakeClock.xcscheme` — shared scheme so `-scheme FakeClock` resolves on CI
- `FakeClock.xcodeproj/project.xcworkspace/contents.xcworkspacedata`
- `.github/workflows/build.yaml` — final CI pipeline (macos-14, clean build unsigned generic iOS → assemble IPA → validate → upload artifact). Supersedes and deletes `ios-build.yml` (its archive+exportArchive path requires a signed archive; the new flow produces an installable unsigned/ad-hoc IPA directly from the build products)
- `FakeClock/Assets.xcassets/Contents.json` — root catalog manifest (was missing)
- `FakeClock/Info.plist` — `UIRequiredDeviceCapabilities` armv7→arm64 (armv7 blocks install on any modern device); CFBundlePackageType literal APPL

## Known limitation (honest statement)

An IPA cannot be produced on this Windows machine — `xcodebuild` does not exist outside macOS. Delivery path: push the repo to GitHub, the `build.yaml` workflow runs on a macOS runner, and `FakeClock.ipa` appears under the run's Artifacts. The IPA is built Release/unsigned (ad-hoc re-sign attempted); sideloading requires AltStore/Sideloadly/escapened or a paid developer provisioning profile applied locally.

## Remaining tasks

1. Push to GitHub → monitor first CI run → fix any compile errors reported by the macOS runner (iterate on sources, rerun `python3 generate_project.py` if files are added/renamed).
2. Optional: add FakeClockTests unit-test target once the base build is green.
