# Handoff

## Session 1: Phase 0, Live Photo spike (2026-10-16)

- **Toolchain:** Xcode 26.5 (17F42) on macOS 26 (M4 Mac mini). Simulator runtimes: iOS 26.5, 26.2 and 17.5 (17.5 was installed this session for the iOS 17 column of the test matrix).
- **Branch / PR:** `phase-0-live-photo-spike` → `main`.

### Done

- Created the GitHub repo `AaronCx/a-plus-wallpaper` at Aaron's request. Claude chose public visibility (D-10, for Aaron to confirm). `main` holds only GitHub's initial commit; everything else is in the Phase 0 PR.
- Repo skeleton: `.gitignore` (covers certificates, profiles, keys and `.env`, though none are needed), `README.md`, and `docs/` with `BRIEF.md`, `DECISIONS.md` (section 8 as open items, plus new item D-6), `RISKS.md` (section 7 plus Phase 0 notes) and this file.
- The `Spike/LivePhotoSpike` throwaway app. No third-party code; Swift 6 with complete strict concurrency; warnings are errors; iOS 17.0 deployment target; iPhone and iPad.
  - **Rendering:** one original Metal compute shader (`SpikeDrift.metal`) renders offscreen at the window scene's native pixel size. Frames go straight into `CVPixelBuffer`s from the writer's pool through a Metal texture cache. Still and video share one code path.
  - **Writing:** a HEIC still (maker-note key 17) and a MOV with the content identifier and a still-image-time track. The track holds one 1-tick sample with value -1, an identity still-image transform and reference dimensions, and references the video track (`tref cdsc`). This matches the camera layout (D-17). All of it is public API except two identifier strings the SDK has no constant for: maker-note "17" and still-image-time.
  - **Saving:** `PHAssetCreationRequest` with `.photo` + `.pairedVideo`.
  - **Debug screen:** saves each of the 12 variants (1.5/2/3 s × 30/60 fps × HEVC/H.264), or all of them. Each frame carries a small label naming its variant, so a Lock Screen shows which one it is. It previews the last pair with `PHLivePhotoView` and can check each saved asset is stored as Live.
  - **Data, not code:** the tunable parameters live in `Spike/LivePhotoSpike/LivePhotoRecipe.json`: the variants, seed, bits per pixel, key-frame interval, frame reordering, still position and HEIC quality, and the still-image-time track options.
    - Fixed in code: codec profile and level, BT.709 colour tags (`LivePhotoMovieWriter.swift`), the 600 timescale, BGRA source buffers, and output size = the screen's native pixels.
- **Tests (Swift Testing, 14 tests; 35 cases counting parameters):**
  - The recipe matrix.
  - Rendering: native size, same output for the same inputs, motion over time.
  - File format, per codec at 30 and 60 fps: identifiers, the still-image-time value, time and duration, identity transform and reference-dimension values, track reference, codec, size, frame count, duration.
  - Photos' own pairing check. Photos must reject mismatched identifiers when loading and when saving; matching pairs at the same size act as the control.
  - **The round trip** (save, read back as `PHLivePhoto`, export the stored resources and re-check the metadata).
  - Every variant saved and read back, each writing a JSON parameter report.
- **Scripts:**
  - `scripts/spike-test.sh` runs the suite on one dedicated simulator and fails on any failed **or skipped** test.
  - `scripts/spike-matrix.sh` runs the section 6 simulator matrix.
  - `scripts/variant-report-table.py` turns the reports into tables.
  - `scripts/check-repo-hygiene.sh` checks there are no secrets, Finder duplicates or spike network hosts.
- **CI:** `.github/workflows/ci.yml` runs the hygiene check on Ubuntu, and the build plus the full suite on `macos-26` (Xcode 26.5 when present). Actions are pinned by SHA.
- **Research** (5 parallel researchers and a reconciler) on what iOS needs for a Live Photo wallpaper to move. The result changes the outlook for the feature; see D-6 in `DECISIONS.md`.

### Simulator test matrix (this session)

`scripts/spike-matrix.sh` ran on the final code. Every row is the full suite with all 12 variants saved to Photos and read back; the per-variant parameters are in `DECISIONS.md`.

| Simulator | iOS | Native size | Tests | Stored as Live | IDs + metadata kept by Photos | Largest MOV |
|---|---|---|---|---|---|---|
| iPhone 17 (iPhone18,3) | 26.5 | 1206x2622 @3x | 14/14 passed, 0 skipped | 12/12 | 12/12 | 10,505 KB (3.0s-60fps-h264) |
| iPhone 17 Pro Max (iPhone18,2) | 26.5 | 1320x2868 @3x | 14/14 passed, 0 skipped | 12/12 | 12/12 | 11,635 KB (3.0s-60fps-h264) |
| iPhone SE (3rd gen) (iPhone14,6) | 26.5 | 750x1334 @2x | 14/14 passed, 0 skipped | 12/12 | 12/12 | 4,295 KB (3.0s-60fps-h264) |
| iPad Pro 13-inch (M5) (iPad17,4) | 26.5 | 2064x2752 @2x | 14/14 passed, 0 skipped | 12/12 | 12/12 | 15,305 KB (3.0s-60fps-h264) |
| iPhone Xs (iPhone11,2) | 17.5 | 1125x2436 @3x | 14/14 passed, 0 skipped | 12/12 | 12/12 | 9,486 KB (3.0s-60fps-h264) |
| iPhone SE (3rd gen) (iPhone14,6) | 17.5 | 750x1334 @2x | 14/14 passed, 0 skipped | 12/12 | 12/12 | 4,293 KB (3.0s-60fps-h264) |
| iPad Pro 13-inch (M4) (iPad16,6) | 17.5 | 2064x2752 @2x | 14/14 passed, 0 skipped | 12/12 | 12/12 | 15,305 KB (3.0s-60fps-h264) |

CI (`macos-26`, Xcode 26.5) runs the same full suite on iPhone 17 / iOS 26.5. No iOS 18 runtime was available (none is installed here, and none is on GitHub's `macos-26` image).

### Next: for Aaron

1. **Review and merge the Phase 0 PR.**
2. **Hardware test.** Expect "Motion Not Available" (see D-6); the test confirms it cheaply.
   1. Open `Spike/LivePhotoSpike.xcodeproj`, choose your team under Signing (the project sets none), and run on a device.
   2. Tap **Save all** and allow adding to Photos. Optionally tap **Check saved variants in Photos** and allow read access.
   3. In Photos, open a variant (the label on the image names it). Tap Share, then **Use as Wallpaper**.
   4. In the editor, look for **Live Effect** in the ••• menu, or a **"Motion Not Available"** tip. Those are the iOS 26 strings; iOS 17 and 18 show a Live Photo button instead.
   5. If motion is offered, add the wallpaper, lock the device, wake it and note whether the Lock Screen moves.
   6. Optional, for a definite yes or no: with the device attached, filter Console.app on process `PhotosPosterProvider` and look for `settlingEffectStatus` while the editor opens.
   7. Record results in the "Phase 0 hardware results" table in `DECISIONS.md`.

   **Fast path:** test the 12 variants on one device first, for example your paired iPhone Air (iOS 27.0.1). If none moves, the remaining iOS versions add little; go to D-6.
3. **Decide** D-6 (motion path) and D-2 to D-5 (licence, art browsing, presets repo name, iOS 17 minimum). Confirm the App Store name "a+wallpaper studio" (D-1) and public visibility (D-10).

### Next: for the following session

- Phase 1 (render core) does not depend on the hardware results and can start once this PR is merged. Phase 2's Live export waits for D-6.
- The spike is throwaway. Phase 1 moves rendering into `Packages/RenderCore`, keeping the PCG-style hash, the explicit `t` and the fixed loop bounds. The Live Photo writer ideas move to `ExportKit` in Phase 2.

### Open questions

- D-6 and its sub-questions: whether to pursue the `live-photo-info` track at all; if so, where the payload would come from legally; and whether to drop to a video long side of 1920 px or less, which several reports say is required and which conflicts with "native pixel size".
- Do iPad Lock Screens play Live Photo motion at all? No authoritative source found.

### Notes and gotchas (verified this session)

- **Simulator Photos access:** `xcrun simctl privacy grant photos` writes a version-1 TCC entry. PhotoKit's read/write check queries version 2, so the app sees "not determined". `spike-test.sh` upgrades the entry in its own simulators only (decision D-13); evidence is in `tccd`'s log.
  - Tests never request access, because an unanswered prompt can leave the grant set to "denied".
- **The simulator can't judge wallpaper motion.** Its wallpaper editor never offers Live Effect, because the on-device ML step behind the "settling effect" fails there. Only hardware answers the question.
- **Simulator encoders are software only, and HEVC is slow.** One simulator's full suite takes about 3-6 minutes locally; the 7-simulator `spike-matrix.sh` about 35-45 minutes; the CI job about 25 minutes on `macos-26`. The simulator's HEVC encoder (VCPHEVC) logs `unrecognised property key` once per movie; the Mac's encoder doesn't, and the output checks out (Main profile, `hvc1`, no reordering, BT.709 tags). It also encodes full-range YUV, while H.264 is video-range. Devices use the hardware encoder, so neither applies there.
- **Simulators created:** this session made dedicated `APW …` simulators. Remove them any time with `xcrun simctl delete <udid>`; `scripts/spike-test.sh` recreates them on demand.
- **Repo path:** the local repo lives at `~/Developer/github/a-plus-wallpaper`. `~/Developer/github/wallpaper-studio` is a symlink to it, kept so the original brief path still works.

## Session 1 follow-up: App Store Connect, device builds and TestFlight (2026-10-18)

At Aaron's request:

- **Bundle IDs registered:** `com.aaroncx.apluswallpaper` (the app) and `com.aaroncx.apluswallpaper.spike` (development installs of the spike).
- **App Store Connect app created.** Details are in D-1. "a+wallpaper" was taken, so the App Store name is "a+wallpaper studio" until Aaron decides.
- **Signing stays out of the repo.** The project sets no team. Development and App Store profiles live in the developer account; pass the team and profile on the command line.
- **Direct device install** needs the device on the Mac's local network or a cable: `devicectl` finds devices with Bonjour, which a VPN doesn't carry.

  ```sh
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
    -project Spike/LivePhotoSpike.xcodeproj -scheme LivePhotoSpike \
    -destination 'generic/platform=iOS' -derivedDataPath build/device/DerivedData build \
    CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=<your team ID> CODE_SIGN_IDENTITY="Apple Development" \
    PROVISIONING_PROFILE_SPECIFIER="<development profile for com.aaroncx.apluswallpaper.spike>"
  xcrun devicectl device install app --device <device> \
    build/device/DerivedData/Build/Products/Debug-iphoneos/LivePhotoSpike.app
  ```

- **TestFlight (D-19):**
  - The spike now has an app icon (`Assets.xcassets`, drawn by `scripts/make-spike-icon.swift`) and `PrivacyInfo.xcprivacy`.
  - Build 0.0.1 (1) is on TestFlight as an internal-only build. It was not launch-tested on a device before upload.
  - To upload again, raise `CURRENT_PROJECT_VERSION` (or pass it on the command line), then archive:

  ```sh
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
    -project Spike/LivePhotoSpike.xcodeproj -scheme LivePhotoSpike \
    -destination 'generic/platform=iOS' archive -archivePath build/LivePhotoSpike.xcarchive \
    CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=<your team ID> CODE_SIGN_IDENTITY="Apple Distribution" \
    PROVISIONING_PROFILE_SPECIFIER="<App Store profile for com.aaroncx.apluswallpaper>" \
    PRODUCT_BUNDLE_IDENTIFIER=com.aaroncx.apluswallpaper
  ```

  Then export with `xcodebuild -exportArchive`, using an export-options plist (ignored by git) with `method` app-store-connect, `destination` upload, manual signing and `testFlightInternalTestingOnly` true. Authenticate with App Store Connect API key flags, and keep the key file outside the repo.
