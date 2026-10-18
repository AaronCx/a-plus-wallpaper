# Decisions

Every decision gets an ID, a status, a date and who made it. Open items wait for Aaron, and only Aaron closes them. Update this file at the end of every session.

## Open: waiting for Aaron

### D-6 (new, blocks Phase 2's Live export): how to get Lock Screen motion, if at all

**Status:** Open. Raised 2026-10-16 by the Phase 0 research. Per the brief, a spike result that contradicts the brief, and any licence question, goes to Aaron.

**What we found** (sources in [Phase 0 research](#phase-0-research-what-ios-needs-for-a-moving-wallpaper)):

- The brief's recipe makes a valid Live Photo. Photos stores it as Live, and the spike's tests prove that on the iOS 17.5 and 26.5 simulators.
- That recipe very likely does **not** move on the Lock Screen on iOS 17 or later. A developer tried almost exactly our matrix (Apple Developer Forums thread 798044: H.264, 30 fps, 1.5, 2 and 3 s, HEIC and JPEG) and got "Motion Not Available" on iOS 17.0 to 18.1. Apple DTS replied that the requirements are undocumented and advised against reverse-engineering them.
- Every community generator that does get motion adds an undocumented `com.apple.quicktime.live-photo-info` timed metadata track. Each one found copies the same 136-byte payload, and its provenance traces back to a commercial app ("Wallpaper Now"). No public constant, documentation or from-scratch payload exists.

**The spike does not use that payload, or any third-party data.** Every variant is written with public SDK APIs. The transform and reference-dimension items use public CoreMedia identifiers (`CMMetadata.h:173-185`). Two identifiers the brief prescribes have no SDK constant: maker-note key `"17"` and `mdta/com.apple.quicktime.still-image-time`. They are undocumented conventions taken from camera files, carrying trivial values. So the baseline already rests on undocumented conventions too. What separates option 3 below is the provenance and licence of a binary payload, not documented versus undocumented.

**Options for Aaron:**

1. **Test first (recommended, cheap).** Run the 12 spike variants on one iOS 26 device. If every variant shows "Motion Not Available", the prediction holds and the rest of the hardware matrix adds little.
2. **v1 ships static wallpapers only.** Live Photo export stays out of the product, or ships labelled as a Live Photo for the Photos app, with no wallpaper-motion claim. Also file an Apple Feedback request for an API that creates wallpaper-capable Live Photos, which DTS suggested.
3. **Use the community payload.** This raises licence and provenance questions (origin is a commercial app, redistributed by MIT-labelled repos), relies on unsupported behaviour any iOS update can break, and adds App Review risk.
4. **Build our own payload by studying camera files.** For example, take one sample from a Live Photo Aaron shoots himself, or synthesise a version-3 payload. This is the reverse-engineering Apple advised against. Reports say moving a camera file's payload onto other video fails, and Apple's own MediaAnalysis framework names further content gates: stabilisation, video quality, still transition and minimum settling duration.

Any motion attempt probably also needs the **video** capped at about 1920 px on the long side, with the still kept at native size (as camera files pair a 4032×3024 still with a 1920×1440 movie). That conflicts with the brief's "native pixel size" and needs a small code change; the recipe JSON doesn't cover output size today.

**Recommendation:** option 1, then option 2 unless the hardware test surprises us. The quickest device is Aaron's paired iPhone Air (iOS 27.0.1).

### D-1: app name and bundle ID

**Status:** decided, except the App Store name (Aaron to confirm).

- **Name: a+wallpaper.** Decided by Aaron, 2026-10-16. This is the name under the home-screen icon.
- **Bundle ID: `com.aaroncx.apluswallpaper`**, to match `com.aaroncx.aplusterminal`. Registered 2026-10-18, when Aaron asked for the App Store Connect app. The spike uses `com.aaroncx.apluswallpaper.spike` (also registered, with a development profile for Aaron's iPhone Air) so it can't collide with the real app on a device.
- **App Store Connect app:** created 2026-10-18 at Aaron's request. Apple ID `6824322347`, SKU `a-plus-wallpaper`, primary language English (U.S.).
- **App Store name: "a+wallpaper studio"**, chosen by Claude because App Store Connect said "a+wallpaper" is already in use. Aaron to confirm. The name can be changed in App Store Connect until the first submission.

### D-2: code licence

**Status:** open. The brief suggests MIT; community presets would be CC0-1.0. Until Aaron decides there is no `LICENSE` file, so the code is "all rights reserved". Shader headers point here.

### D-3: art browsing, curated or open search

**Status:** open. Blocks Phase 3. The brief recommends starting curated (lower age rating, see risk 5).

### D-4: community presets repo name

**Status:** open. Blocks Phase 4. A suggestion that follows this repo's naming is `a-plus-wallpaper-presets`.

### D-5: iOS 17 as the minimum

**Status:** open, assumed for now. The spike targets iOS 17.0, and every symbol it uses compiles at 17.0. The full suite (14 tests, all 12 variants) passes on iOS 17.5 on iPhone Xs (the oldest iPhone iOS 17 supports), iPhone SE (3rd gen) and iPad Pro 13-inch (M4). See the per-simulator table below.

## Decided

| ID | Date | Decision | By | Why |
|----|------|----------|----|-----|
| D-10 | 2026-10-16 | Repository `AaronCx/a-plus-wallpaper`, public, default branch `main` (first commit made by GitHub, so nothing was pushed to `main`) | Aaron asked for the repo and the name; **visibility chosen by Claude, for Aaron to confirm** | GitHub repo names can't contain `+`; follows `a-plus-terminal`. Public because the brief calls the project open source, and public repos get free macOS CI minutes. There's no `LICENSE` until D-2, so the code is "all rights reserved" meanwhile. |
| D-11 | 2026-10-16 | The Xcode project is hand-written (objectVersion 77, synchronized folders), not generated by XcodeGen | Claude | The brief allows zero dependencies by default. Synchronized folders keep the project file small and stable. |
| D-12 | 2026-10-16 | Tests use Swift Testing. `scripts/spike-test.sh` fails on any skipped test, not only failed ones | Claude | A skipped Photos test must never look like a pass. |
| D-13 | 2026-10-16 | Simulator Photos access: after `simctl privacy grant photos`, the test script upgrades that TCC entry to `auth_version=2`, only in its own `APW …` simulators | Claude | `simctl` writes a version-1 entry, but PhotoKit's read/write check queries version 2 and reports "not determined" without one. Seen in `tccd`'s log on iOS 17.5 and 26.5. |
| D-14 | 2026-10-16 | CI on GitHub Actions: `macos-26` for build and tests, `ubuntu-latest` for repo hygiene. `actions/checkout` pinned to the full commit SHA of v7.0.1 | Claude | Matches `a-plus-terminal`'s runner. Pinning follows risk 15. |
| D-15 | 2026-10-16 | The spike asks for read/write Photos access, but only for its "check saved variants" button and its tests. Saving uses add-only. The product will use add-only (brief, Phase 2) | Claude | Reading assets back is the only way to prove Photos stored a Live Photo. |
| D-16 | 2026-10-16 | Each spike frame and still carries a small burned-in label naming its variant | Claude | Once a wallpaper is set, the label is the only reliable way to tell the 12 variants apart on a Lock Screen. It is static, so the still still matches the video frame exactly. |
| D-17 | 2026-10-16 | The still-image-time track follows the camera layout: one 1-tick sample at the still time holding `still-image-time` = -1, an identity still-image transform and its reference dimensions, plus `tref cdsc` to the video | Claude | All public identifiers, except the still-image-time string itself. It matches iOS 26 and 27 camera files. Photos pairs either way; this just keeps our files as close to camera files as public API allows. |
| D-18 | 2026-10-16 | Still at frame floor(frames × 0.5), which is always at least 0.5 s into the clip | Claude | Camera files put the still near mid-clip. Reports say a key photo in the first ~0.33 s gives "Motion Not Available". |
| D-19 | 2026-10-18 | The spike goes to TestFlight as an internal-only build of the real app record ("a+wallpaper studio"). The archive overrides the bundle ID to `com.aaroncx.apluswallpaper`; the project keeps `.spike` for development installs | Aaron asked for TestFlight; Claude chose the setup | A direct install needs the device on the Mac's local network or a cable; TestFlight reaches it anywhere. An upload needs an app icon (now drawn by `scripts/make-spike-icon.swift`, original work) and a privacy manifest declaring `UserDefaults` (reason CA92.1, for the spike's launch flag). The home-screen name stays "a+wallpaper spike", and the build is internal-only, so it can never reach the App Store. |

## Phase 0: exact parameters of each Live Photo variant

Measured on 2026-10-16 from the written files **and** from what Photos stored, by `scripts/spike-matrix.sh` (Xcode 26.5) on 7 simulators. Every variant is stored as a Live Photo on every simulator, with its identifiers and timed metadata intact.

Shared by every variant (recipe schema 1):

- Shader `spikeDrift`, seed 20261016, rendered at the screen's native pixel size, BGRA 8-bit, sRGB.
- Still: HEIC, quality 0.9, maker-note key "17" = content identifier; the exact frame at the still time (frame index = floor(frames x 0.5)).
- Movie: QuickTime `.mov`, timescale 600, constant frame rate, no audio; top-level `com.apple.quicktime.content.identifier` (UTF-8).
- Video: HEVC Main AutoLevel (`hvc1`) or H.264 High AutoLevel (`avc1`); BT.709 primaries, transfer and matrix; key frame every 1s; frame reordering off; average bit rate = bits-per-pixel x width x height x fps with bits-per-pixel h264 0.12, hevc 0.08.
- Timed metadata: one `mebx` track, one sample of 1 tick(s) at the still time: `still-image-time` (int8) = -1, identity `live-photo-still-image-transform` (3x3 float64) and `...reference-dimensions` (float32, the video size); the track references the video track (`tref cdsc`).
- Saved with one `PHAssetCreationRequest`: `.photo` (HEIC) + `.pairedVideo` (MOV).

**Per variant** (the same on every device except the pixel size, which is always the screen's native size):

| Variant | Duration | fps | Frames | Still frame (time; ticks) | Codec / profile | Key frame | Average bit rate (bit/s) |
|---|---|---|---|---|---|---|---|
| 1.5s-30fps-h264 | 1.5 s | 30 | 45 | 22 (0.733 s; 440/600) | H.264 High AutoLevel (`avc1`) | 30 frames (1 s) | 0.12 × w × h × 30 |
| 1.5s-30fps-hevc | 1.5 s | 30 | 45 | 22 (0.733 s; 440/600) | HEVC Main AutoLevel (`hvc1`) | 30 frames (1 s) | 0.08 × w × h × 30 |
| 1.5s-60fps-h264 | 1.5 s | 60 | 90 | 45 (0.750 s; 450/600) | H.264 High AutoLevel (`avc1`) | 60 frames (1 s) | 0.12 × w × h × 60 |
| 1.5s-60fps-hevc | 1.5 s | 60 | 90 | 45 (0.750 s; 450/600) | HEVC Main AutoLevel (`hvc1`) | 60 frames (1 s) | 0.08 × w × h × 60 |
| 2.0s-30fps-h264 | 2 s | 30 | 60 | 30 (1.000 s; 600/600) | H.264 High AutoLevel (`avc1`) | 30 frames (1 s) | 0.12 × w × h × 30 |
| 2.0s-30fps-hevc | 2 s | 30 | 60 | 30 (1.000 s; 600/600) | HEVC Main AutoLevel (`hvc1`) | 30 frames (1 s) | 0.08 × w × h × 30 |
| 2.0s-60fps-h264 | 2 s | 60 | 120 | 60 (1.000 s; 600/600) | H.264 High AutoLevel (`avc1`) | 60 frames (1 s) | 0.12 × w × h × 60 |
| 2.0s-60fps-hevc | 2 s | 60 | 120 | 60 (1.000 s; 600/600) | HEVC Main AutoLevel (`hvc1`) | 60 frames (1 s) | 0.08 × w × h × 60 |
| 3.0s-30fps-h264 | 3 s | 30 | 90 | 45 (1.500 s; 900/600) | H.264 High AutoLevel (`avc1`) | 30 frames (1 s) | 0.12 × w × h × 30 |
| 3.0s-30fps-hevc | 3 s | 30 | 90 | 45 (1.500 s; 900/600) | HEVC Main AutoLevel (`hvc1`) | 30 frames (1 s) | 0.08 × w × h × 30 |
| 3.0s-60fps-h264 | 3 s | 60 | 180 | 90 (1.500 s; 900/600) | H.264 High AutoLevel (`avc1`) | 60 frames (1 s) | 0.12 × w × h × 60 |
| 3.0s-60fps-hevc | 3 s | 60 | 180 | 90 (1.500 s; 900/600) | HEVC Main AutoLevel (`hvc1`) | 60 frames (1 s) | 0.08 × w × h × 60 |

**Per simulator** (full suite: 14 tests, 12 variants saved and read back):

| Simulator | iOS | Native size | Tests | Stored as Live | IDs + metadata kept by Photos | Largest MOV |
|---|---|---|---|---|---|---|
| iPhone 17 (iPhone18,3) | 26.5 | 1206x2622 @3x | 14/14 passed, 0 skipped | 12/12 | 12/12 | 10,505 KB (3.0s-60fps-h264) |
| iPhone 17 Pro Max (iPhone18,2) | 26.5 | 1320x2868 @3x | 14/14 passed, 0 skipped | 12/12 | 12/12 | 11,635 KB (3.0s-60fps-h264) |
| iPhone SE (3rd gen) (iPhone14,6) | 26.5 | 750x1334 @2x | 14/14 passed, 0 skipped | 12/12 | 12/12 | 4,295 KB (3.0s-60fps-h264) |
| iPad Pro 13-inch (M5) (iPad17,4) | 26.5 | 2064x2752 @2x | 14/14 passed, 0 skipped | 12/12 | 12/12 | 15,305 KB (3.0s-60fps-h264) |
| iPhone Xs (iPhone11,2) | 17.5 | 1125x2436 @3x | 14/14 passed, 0 skipped | 12/12 | 12/12 | 9,486 KB (3.0s-60fps-h264) |
| iPhone SE (3rd gen) (iPhone14,6) | 17.5 | 750x1334 @2x | 14/14 passed, 0 skipped | 12/12 | 12/12 | 4,293 KB (3.0s-60fps-h264) |
| iPad Pro 13-inch (M4) (iPad16,6) | 17.5 | 2064x2752 @2x | 14/14 passed, 0 skipped | 12/12 | 12/12 | 15,305 KB (3.0s-60fps-h264) |

The simulator's encoders are software-only, so its measured bit rates (in the tables below) say nothing about devices. H.264 overshoots its target there by up to about 1.6×.

<details><summary>Full measured tables, one per simulator</summary>

**iPhone18,3, iOS 26.5, native 1206x2622 @3x**

| Variant | Frames | Still frame (s) | Codec | Video px | Key frame every | Target Mbit/s | Measured Mbit/s | MOV KB | HEIC KB | Still sample | Photos: Live? | Photos kept IDs + metadata? |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1.5s-30fps-h264 | 45 | 22 (0.733) | avc1 | 1206x2622 | 30 frames | 11.4 | 16.6 | 3050 | 104 | -1 @ 0.733s for 1 tick + transform, dims, cdsc | yes | yes |
| 1.5s-30fps-hevc | 45 | 22 (0.733) | hvc1 | 1206x2622 | 30 frames | 7.6 | 8.0 | 1469 | 104 | -1 @ 0.733s for 1 tick + transform, dims, cdsc | yes | yes |
| 1.5s-60fps-h264 | 90 | 45 (0.750) | avc1 | 1206x2622 | 60 frames | 22.8 | 28.7 | 5264 | 104 | -1 @ 0.750s for 1 tick + transform, dims, cdsc | yes | yes |
| 1.5s-60fps-hevc | 90 | 45 (0.750) | hvc1 | 1206x2622 | 60 frames | 15.2 | 15.9 | 2917 | 103 | -1 @ 0.750s for 1 tick + transform, dims, cdsc | yes | yes |
| 2.0s-30fps-h264 | 60 | 30 (1.000) | avc1 | 1206x2622 | 30 frames | 11.4 | 16.3 | 3989 | 104 | -1 @ 1.000s for 1 tick + transform, dims, cdsc | yes | yes |
| 2.0s-30fps-hevc | 60 | 30 (1.000) | hvc1 | 1206x2622 | 30 frames | 7.6 | 7.9 | 1927 | 103 | -1 @ 1.000s for 1 tick + transform, dims, cdsc | yes | yes |
| 2.0s-60fps-h264 | 120 | 60 (1.000) | avc1 | 1206x2622 | 60 frames | 22.8 | 28.5 | 6959 | 104 | -1 @ 1.000s for 1 tick + transform, dims, cdsc | yes | yes |
| 2.0s-60fps-hevc | 120 | 60 (1.000) | hvc1 | 1206x2622 | 60 frames | 15.2 | 15.7 | 3843 | 103 | -1 @ 1.000s for 1 tick + transform, dims, cdsc | yes | yes |
| 3.0s-30fps-h264 | 90 | 45 (1.500) | avc1 | 1206x2622 | 30 frames | 11.4 | 16.1 | 5911 | 104 | -1 @ 1.500s for 1 tick + transform, dims, cdsc | yes | yes |
| 3.0s-30fps-hevc | 90 | 45 (1.500) | hvc1 | 1206x2622 | 30 frames | 7.6 | 7.8 | 2874 | 103 | -1 @ 1.500s for 1 tick + transform, dims, cdsc | yes | yes |
| 3.0s-60fps-h264 | 180 | 90 (1.500) | avc1 | 1206x2622 | 60 frames | 22.8 | 28.7 | 10505 | 104 | -1 @ 1.500s for 1 tick + transform, dims, cdsc | yes | yes |
| 3.0s-60fps-hevc | 180 | 90 (1.500) | hvc1 | 1206x2622 | 60 frames | 15.2 | 15.6 | 5724 | 103 | -1 @ 1.500s for 1 tick + transform, dims, cdsc | yes | yes |

**iPhone18,2, iOS 26.5, native 1320x2868 @3x**

| Variant | Frames | Still frame (s) | Codec | Video px | Key frame every | Target Mbit/s | Measured Mbit/s | MOV KB | HEIC KB | Still sample | Photos: Live? | Photos kept IDs + metadata? |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1.5s-30fps-h264 | 45 | 22 (0.733) | avc1 | 1320x2868 | 30 frames | 13.6 | 18.7 | 3426 | 113 | -1 @ 0.733s for 1 tick + transform, dims, cdsc | yes | yes |
| 1.5s-30fps-hevc | 45 | 22 (0.733) | hvc1 | 1320x2868 | 30 frames | 9.1 | 9.6 | 1752 | 113 | -1 @ 0.733s for 1 tick + transform, dims, cdsc | yes | yes |
| 1.5s-60fps-h264 | 90 | 45 (0.750) | avc1 | 1320x2868 | 60 frames | 27.3 | 32.1 | 5877 | 113 | -1 @ 0.750s for 1 tick + transform, dims, cdsc | yes | yes |
| 1.5s-60fps-hevc | 90 | 45 (0.750) | hvc1 | 1320x2868 | 60 frames | 18.2 | 19.0 | 3480 | 112 | -1 @ 0.750s for 1 tick + transform, dims, cdsc | yes | yes |
| 2.0s-30fps-h264 | 60 | 30 (1.000) | avc1 | 1320x2868 | 30 frames | 13.6 | 18.4 | 4496 | 113 | -1 @ 1.000s for 1 tick + transform, dims, cdsc | yes | yes |
| 2.0s-30fps-hevc | 60 | 30 (1.000) | hvc1 | 1320x2868 | 30 frames | 9.1 | 9.4 | 2286 | 113 | -1 @ 1.000s for 1 tick + transform, dims, cdsc | yes | yes |
| 2.0s-60fps-h264 | 120 | 60 (1.000) | avc1 | 1320x2868 | 60 frames | 27.3 | 31.7 | 7743 | 113 | -1 @ 1.000s for 1 tick + transform, dims, cdsc | yes | yes |
| 2.0s-60fps-hevc | 120 | 60 (1.000) | hvc1 | 1320x2868 | 60 frames | 18.2 | 18.7 | 4558 | 113 | -1 @ 1.000s for 1 tick + transform, dims, cdsc | yes | yes |
| 3.0s-30fps-h264 | 90 | 45 (1.500) | avc1 | 1320x2868 | 30 frames | 13.6 | 18.4 | 6741 | 113 | -1 @ 1.500s for 1 tick + transform, dims, cdsc | yes | yes |
| 3.0s-30fps-hevc | 90 | 45 (1.500) | hvc1 | 1320x2868 | 30 frames | 9.1 | 9.3 | 3396 | 112 | -1 @ 1.500s for 1 tick + transform, dims, cdsc | yes | yes |
| 3.0s-60fps-h264 | 180 | 90 (1.500) | avc1 | 1320x2868 | 60 frames | 27.3 | 31.8 | 11635 | 113 | -1 @ 1.500s for 1 tick + transform, dims, cdsc | yes | yes |
| 3.0s-60fps-hevc | 180 | 90 (1.500) | hvc1 | 1320x2868 | 60 frames | 18.2 | 18.6 | 6815 | 112 | -1 @ 1.500s for 1 tick + transform, dims, cdsc | yes | yes |

**iPhone14,6, iOS 26.5, native 750x1334 @2x**

| Variant | Frames | Still frame (s) | Codec | Video px | Key frame every | Target Mbit/s | Measured Mbit/s | MOV KB | HEIC KB | Still sample | Photos: Live? | Photos kept IDs + metadata? |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1.5s-30fps-h264 | 45 | 22 (0.733) | avc1 | 750x1334 | 30 frames | 3.6 | 3.7 | 673 | 50 | -1 @ 0.733s for 1 tick + transform, dims, cdsc | yes | yes |
| 1.5s-30fps-hevc | 45 | 22 (0.733) | hvc1 | 750x1334 | 30 frames | 2.4 | 2.5 | 456 | 50 | -1 @ 0.733s for 1 tick + transform, dims, cdsc | yes | yes |
| 1.5s-60fps-h264 | 90 | 45 (0.750) | avc1 | 750x1334 | 60 frames | 7.2 | 12.1 | 2219 | 50 | -1 @ 0.750s for 1 tick + transform, dims, cdsc | yes | yes |
| 1.5s-60fps-hevc | 90 | 45 (0.750) | hvc1 | 750x1334 | 60 frames | 4.8 | 5.0 | 913 | 50 | -1 @ 0.750s for 1 tick + transform, dims, cdsc | yes | yes |
| 2.0s-30fps-h264 | 60 | 30 (1.000) | avc1 | 750x1334 | 30 frames | 3.6 | 3.6 | 888 | 50 | -1 @ 1.000s for 1 tick + transform, dims, cdsc | yes | yes |
| 2.0s-30fps-hevc | 60 | 30 (1.000) | hvc1 | 750x1334 | 30 frames | 2.4 | 2.5 | 601 | 50 | -1 @ 1.000s for 1 tick + transform, dims, cdsc | yes | yes |
| 2.0s-60fps-h264 | 120 | 60 (1.000) | avc1 | 750x1334 | 60 frames | 7.2 | 11.9 | 2915 | 50 | -1 @ 1.000s for 1 tick + transform, dims, cdsc | yes | yes |
| 2.0s-60fps-hevc | 120 | 60 (1.000) | hvc1 | 750x1334 | 60 frames | 4.8 | 4.9 | 1201 | 50 | -1 @ 1.000s for 1 tick + transform, dims, cdsc | yes | yes |
| 3.0s-30fps-h264 | 90 | 45 (1.500) | avc1 | 750x1334 | 30 frames | 3.6 | 3.7 | 1341 | 49 | -1 @ 1.500s for 1 tick + transform, dims, cdsc | yes | yes |
| 3.0s-30fps-hevc | 90 | 45 (1.500) | hvc1 | 750x1334 | 30 frames | 2.4 | 2.5 | 900 | 49 | -1 @ 1.500s for 1 tick + transform, dims, cdsc | yes | yes |
| 3.0s-60fps-h264 | 180 | 90 (1.500) | avc1 | 750x1334 | 60 frames | 7.2 | 11.7 | 4295 | 49 | -1 @ 1.500s for 1 tick + transform, dims, cdsc | yes | yes |
| 3.0s-60fps-hevc | 180 | 90 (1.500) | hvc1 | 750x1334 | 60 frames | 4.8 | 4.9 | 1800 | 49 | -1 @ 1.500s for 1 tick + transform, dims, cdsc | yes | yes |

**iPad17,4, iPadOS 26.5, native 2064x2752 @2x**

| Variant | Frames | Still frame (s) | Codec | Video px | Key frame every | Target Mbit/s | Measured Mbit/s | MOV KB | HEIC KB | Still sample | Photos: Live? | Photos kept IDs + metadata? |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1.5s-30fps-h264 | 45 | 22 (0.733) | avc1 | 2064x2752 | 30 frames | 20.4 | 23.8 | 4355 | 132 | -1 @ 0.733s for 1 tick + transform, dims, cdsc | yes | yes |
| 1.5s-30fps-hevc | 45 | 22 (0.733) | hvc1 | 2064x2752 | 30 frames | 13.6 | 14.4 | 2644 | 132 | -1 @ 0.733s for 1 tick + transform, dims, cdsc | yes | yes |
| 1.5s-60fps-h264 | 90 | 45 (0.750) | avc1 | 2064x2752 | 60 frames | 40.9 | 41.3 | 7558 | 132 | -1 @ 0.750s for 1 tick + transform, dims, cdsc | yes | yes |
| 1.5s-60fps-hevc | 90 | 45 (0.750) | hvc1 | 2064x2752 | 60 frames | 27.3 | 28.0 | 5126 | 132 | -1 @ 0.750s for 1 tick + transform, dims, cdsc | yes | yes |
| 2.0s-30fps-h264 | 60 | 30 (1.000) | avc1 | 2064x2752 | 30 frames | 20.4 | 23.5 | 5727 | 132 | -1 @ 1.000s for 1 tick + transform, dims, cdsc | yes | yes |
| 2.0s-30fps-hevc | 60 | 30 (1.000) | hvc1 | 2064x2752 | 30 frames | 13.6 | 14.1 | 3452 | 131 | -1 @ 1.000s for 1 tick + transform, dims, cdsc | yes | yes |
| 2.0s-60fps-h264 | 120 | 60 (1.000) | avc1 | 2064x2752 | 60 frames | 40.9 | 41.1 | 10040 | 132 | -1 @ 1.000s for 1 tick + transform, dims, cdsc | yes | yes |
| 2.0s-60fps-hevc | 120 | 60 (1.000) | hvc1 | 2064x2752 | 60 frames | 27.3 | 27.7 | 6761 | 131 | -1 @ 1.000s for 1 tick + transform, dims, cdsc | yes | yes |
| 3.0s-30fps-h264 | 90 | 45 (1.500) | avc1 | 2064x2752 | 30 frames | 20.4 | 23.7 | 8672 | 129 | -1 @ 1.500s for 1 tick + transform, dims, cdsc | yes | yes |
| 3.0s-30fps-hevc | 90 | 45 (1.500) | hvc1 | 2064x2752 | 30 frames | 13.6 | 14.1 | 5160 | 128 | -1 @ 1.500s for 1 tick + transform, dims, cdsc | yes | yes |
| 3.0s-60fps-h264 | 180 | 90 (1.500) | avc1 | 2064x2752 | 60 frames | 40.9 | 41.8 | 15305 | 129 | -1 @ 1.500s for 1 tick + transform, dims, cdsc | yes | yes |
| 3.0s-60fps-hevc | 180 | 90 (1.500) | hvc1 | 2064x2752 | 60 frames | 27.3 | 27.7 | 10151 | 128 | -1 @ 1.500s for 1 tick + transform, dims, cdsc | yes | yes |

**iPhone11,2, iOS 17.5, native 1125x2436 @3x**

| Variant | Frames | Still frame (s) | Codec | Video px | Key frame every | Target Mbit/s | Measured Mbit/s | MOV KB | HEIC KB | Still sample | Photos: Live? | Photos kept IDs + metadata? |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1.5s-30fps-h264 | 45 | 22 (0.733) | avc1 | 1125x2436 | 30 frames | 9.9 | 14.8 | 2706 | 94 | -1 @ 0.733s for 1 tick + transform, dims, cdsc | yes | yes |
| 1.5s-30fps-hevc | 45 | 22 (0.733) | hvc1 | 1125x2436 | 30 frames | 6.6 | 6.9 | 1269 | 94 | -1 @ 0.733s for 1 tick + transform, dims, cdsc | yes | yes |
| 1.5s-60fps-h264 | 90 | 45 (0.750) | avc1 | 1125x2436 | 60 frames | 19.7 | 25.7 | 4710 | 94 | -1 @ 0.750s for 1 tick + transform, dims, cdsc | yes | yes |
| 1.5s-60fps-hevc | 90 | 45 (0.750) | hvc1 | 1125x2436 | 60 frames | 13.2 | 13.8 | 2522 | 93 | -1 @ 0.750s for 1 tick + transform, dims, cdsc | yes | yes |
| 2.0s-30fps-h264 | 60 | 30 (1.000) | avc1 | 1125x2436 | 30 frames | 9.9 | 14.6 | 3565 | 94 | -1 @ 1.000s for 1 tick + transform, dims, cdsc | yes | yes |
| 2.0s-30fps-hevc | 60 | 30 (1.000) | hvc1 | 1125x2436 | 30 frames | 6.6 | 6.8 | 1664 | 94 | -1 @ 1.000s for 1 tick + transform, dims, cdsc | yes | yes |
| 2.0s-60fps-h264 | 120 | 60 (1.000) | avc1 | 1125x2436 | 60 frames | 19.7 | 25.4 | 6205 | 95 | -1 @ 1.000s for 1 tick + transform, dims, cdsc | yes | yes |
| 2.0s-60fps-hevc | 120 | 60 (1.000) | hvc1 | 1125x2436 | 60 frames | 13.2 | 13.6 | 3320 | 94 | -1 @ 1.000s for 1 tick + transform, dims, cdsc | yes | yes |
| 3.0s-30fps-h264 | 90 | 45 (1.500) | avc1 | 1125x2436 | 30 frames | 9.9 | 14.3 | 5239 | 92 | -1 @ 1.500s for 1 tick + transform, dims, cdsc | yes | yes |
| 3.0s-30fps-hevc | 90 | 45 (1.500) | hvc1 | 1125x2436 | 30 frames | 6.6 | 6.8 | 2479 | 92 | -1 @ 1.500s for 1 tick + transform, dims, cdsc | yes | yes |
| 3.0s-60fps-h264 | 180 | 90 (1.500) | avc1 | 1125x2436 | 60 frames | 19.7 | 25.9 | 9486 | 93 | -1 @ 1.500s for 1 tick + transform, dims, cdsc | yes | yes |
| 3.0s-60fps-hevc | 180 | 90 (1.500) | hvc1 | 1125x2436 | 60 frames | 13.2 | 13.6 | 4969 | 92 | -1 @ 1.500s for 1 tick + transform, dims, cdsc | yes | yes |

**iPhone14,6, iOS 17.5, native 750x1334 @2x**

| Variant | Frames | Still frame (s) | Codec | Video px | Key frame every | Target Mbit/s | Measured Mbit/s | MOV KB | HEIC KB | Still sample | Photos: Live? | Photos kept IDs + metadata? |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1.5s-30fps-h264 | 45 | 22 (0.733) | avc1 | 750x1334 | 30 frames | 3.6 | 3.7 | 673 | 50 | -1 @ 0.733s for 1 tick + transform, dims, cdsc | yes | yes |
| 1.5s-30fps-hevc | 45 | 22 (0.733) | hvc1 | 750x1334 | 30 frames | 2.4 | 2.5 | 456 | 50 | -1 @ 0.733s for 1 tick + transform, dims, cdsc | yes | yes |
| 1.5s-60fps-h264 | 90 | 45 (0.750) | avc1 | 750x1334 | 60 frames | 7.2 | 12.1 | 2221 | 50 | -1 @ 0.750s for 1 tick + transform, dims, cdsc | yes | yes |
| 1.5s-60fps-hevc | 90 | 45 (0.750) | hvc1 | 750x1334 | 60 frames | 4.8 | 5.0 | 914 | 50 | -1 @ 0.750s for 1 tick + transform, dims, cdsc | yes | yes |
| 2.0s-30fps-h264 | 60 | 30 (1.000) | avc1 | 750x1334 | 30 frames | 3.6 | 3.6 | 889 | 50 | -1 @ 1.000s for 1 tick + transform, dims, cdsc | yes | yes |
| 2.0s-30fps-hevc | 60 | 30 (1.000) | hvc1 | 750x1334 | 30 frames | 2.4 | 2.5 | 601 | 50 | -1 @ 1.000s for 1 tick + transform, dims, cdsc | yes | yes |
| 2.0s-60fps-h264 | 120 | 60 (1.000) | avc1 | 750x1334 | 60 frames | 7.2 | 11.9 | 2917 | 50 | -1 @ 1.000s for 1 tick + transform, dims, cdsc | yes | yes |
| 2.0s-60fps-hevc | 120 | 60 (1.000) | hvc1 | 750x1334 | 60 frames | 4.8 | 4.9 | 1204 | 50 | -1 @ 1.000s for 1 tick + transform, dims, cdsc | yes | yes |
| 3.0s-30fps-h264 | 90 | 45 (1.500) | avc1 | 750x1334 | 30 frames | 3.6 | 3.7 | 1341 | 49 | -1 @ 1.500s for 1 tick + transform, dims, cdsc | yes | yes |
| 3.0s-30fps-hevc | 90 | 45 (1.500) | hvc1 | 750x1334 | 30 frames | 2.4 | 2.4 | 898 | 49 | -1 @ 1.500s for 1 tick + transform, dims, cdsc | yes | yes |
| 3.0s-60fps-h264 | 180 | 90 (1.500) | avc1 | 750x1334 | 60 frames | 7.2 | 11.7 | 4293 | 49 | -1 @ 1.500s for 1 tick + transform, dims, cdsc | yes | yes |
| 3.0s-60fps-hevc | 180 | 90 (1.500) | hvc1 | 750x1334 | 60 frames | 4.8 | 4.9 | 1797 | 49 | -1 @ 1.500s for 1 tick + transform, dims, cdsc | yes | yes |

**iPad16,6, iPadOS 17.5, native 2064x2752 @2x**

| Variant | Frames | Still frame (s) | Codec | Video px | Key frame every | Target Mbit/s | Measured Mbit/s | MOV KB | HEIC KB | Still sample | Photos: Live? | Photos kept IDs + metadata? |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1.5s-30fps-h264 | 45 | 22 (0.733) | avc1 | 2064x2752 | 30 frames | 20.4 | 23.8 | 4354 | 132 | -1 @ 0.733s for 1 tick + transform, dims, cdsc | yes | yes |
| 1.5s-30fps-hevc | 45 | 22 (0.733) | hvc1 | 2064x2752 | 30 frames | 13.6 | 14.4 | 2641 | 132 | -1 @ 0.733s for 1 tick + transform, dims, cdsc | yes | yes |
| 1.5s-60fps-h264 | 90 | 45 (0.750) | avc1 | 2064x2752 | 60 frames | 40.9 | 41.3 | 7558 | 132 | -1 @ 0.750s for 1 tick + transform, dims, cdsc | yes | yes |
| 1.5s-60fps-hevc | 90 | 45 (0.750) | hvc1 | 2064x2752 | 60 frames | 27.3 | 28.0 | 5126 | 132 | -1 @ 0.750s for 1 tick + transform, dims, cdsc | yes | yes |
| 2.0s-30fps-h264 | 60 | 30 (1.000) | avc1 | 2064x2752 | 30 frames | 20.4 | 23.4 | 5725 | 132 | -1 @ 1.000s for 1 tick + transform, dims, cdsc | yes | yes |
| 2.0s-30fps-hevc | 60 | 30 (1.000) | hvc1 | 2064x2752 | 30 frames | 13.6 | 14.1 | 3450 | 131 | -1 @ 1.000s for 1 tick + transform, dims, cdsc | yes | yes |
| 2.0s-60fps-h264 | 120 | 60 (1.000) | avc1 | 2064x2752 | 60 frames | 40.9 | 41.1 | 10043 | 132 | -1 @ 1.000s for 1 tick + transform, dims, cdsc | yes | yes |
| 2.0s-60fps-hevc | 120 | 60 (1.000) | hvc1 | 2064x2752 | 60 frames | 27.3 | 27.7 | 6758 | 131 | -1 @ 1.000s for 1 tick + transform, dims, cdsc | yes | yes |
| 3.0s-30fps-h264 | 90 | 45 (1.500) | avc1 | 2064x2752 | 30 frames | 20.4 | 23.7 | 8670 | 129 | -1 @ 1.500s for 1 tick + transform, dims, cdsc | yes | yes |
| 3.0s-30fps-hevc | 90 | 45 (1.500) | hvc1 | 2064x2752 | 30 frames | 13.6 | 14.1 | 5157 | 128 | -1 @ 1.500s for 1 tick + transform, dims, cdsc | yes | yes |
| 3.0s-60fps-h264 | 180 | 90 (1.500) | avc1 | 2064x2752 | 60 frames | 40.9 | 41.8 | 15305 | 129 | -1 @ 1.500s for 1 tick + transform, dims, cdsc | yes | yes |
| 3.0s-60fps-hevc | 180 | 90 (1.500) | hvc1 | 2064x2752 | 60 frames | 27.3 | 27.7 | 10142 | 128 | -1 @ 1.500s for 1 tick + transform, dims, cdsc | yes | yes |

</details>

## Phase 0 hardware results (Aaron)

For each variant and iOS version, fill in **M** (moves on the Lock Screen), **N** ("Motion Not Available", or no Live Photo / Live Effect option) or **–** (not tested). Note the device model next to each iOS version.

| Variant | iOS 17.x (device: ) | iOS 18.x (device: ) | iOS 26.x (device: ) | iOS 27.x (device: ) |
|---|---|---|---|---|
| 1.5s-30fps-hevc | | | | |
| 1.5s-30fps-h264 | | | | |
| 1.5s-60fps-hevc | | | | |
| 1.5s-60fps-h264 | | | | |
| 2.0s-30fps-hevc | | | | |
| 2.0s-30fps-h264 | | | | |
| 2.0s-60fps-hevc | | | | |
| 2.0s-60fps-h264 | | | | |
| 3.0s-30fps-hevc | | | | |
| 3.0s-30fps-h264 | | | | |
| 3.0s-60fps-hevc | | | | |
| 3.0s-60fps-h264 | | | | |

Also note any iPad result separately; no source says whether iPadOS plays Live Photo wallpaper motion.

## Phase 0 research: what iOS needs for a moving wallpaper

Five researchers worked in parallel on 2026-10-16: two independent web reviews of the file format, one on SDK ground truth, one on CI runners and one simulator probe. A sixth agent reconciled their results. Facts only; no third-party code was copied. Confidence levels are as the researchers reported them.

**Verified against the installed iOS 26.5 SDK or by experiment**

- The still's content identifier goes under maker-note key `"17"` in `kCGImagePropertyMakerAppleDictionary`. The SDK has no constant for that key.
- The movie's identifier is `AVMetadataIdentifier.quickTimeMetadataContentIdentifier` (`mdta/com.apple.quicktime.content.identifier`, UTF-8).
- `mdta/com.apple.quicktime.still-image-time` has no public constant; the spike spells it out. Its data type is `kCMMetadataBaseDataType_SInt8`. Camera files store **-1**. Photos takes the key-photo time from the sample's timestamp, not its value.
- `kCMMetadataIdentifier_QuickTimeMetadataLivePhotoStillImageTransform` and its `…ReferenceDimensions` partner are public (`CoreMedia/CMMetadata.h:173-185`, iOS 13). Camera files carry them in the same sample as still-image-time.
- For Photos, matching identifiers are all that matters. With matching identifiers, Photos stores the pair as Live even without the still-image-time track; with mismatched ones, the save fails (PHPhotosErrorDomain 3302 on iOS 26.5). So the round-trip test proves **pairing**, not wallpaper eligibility.
- In the iOS 26.5 runtime the wallpaper-motion feature is internally the "settling effect" (UI name **Live Effect**). Its failure tip reads **"Motion Not Available — Motion from this Live Photo is not supported as a wallpaper."** (strings in `PhotosUICore.framework` and `PhotosUIPrivate.framework`).

**Well sourced (several independent reports)**

- Apple DTS, Apple Developer Forums thread 798044 (August 2025): Live Photos usable as motion wallpapers have "undocumented requirements"; reverse-engineering them is "very fragile and is not supported". DTS suggests filing an enhancement request.
  - The reporter's files are essentially our recipe: 882×1920, H.264, 30 fps, 1.5, 2 and 3 s, still-image-time at mid-clip.
  - They show "Motion Not Available" on iOS 17.0 to 18.1.
- Generators that do get motion all add a per-frame `mdta/com.apple.quicktime.live-photo-info` timed metadata track.
  - It is private: no public constant, and setup data naming a device build.
  - Each frame carries a 136-byte version-3 payload.
  - Every open-source generator found reuses one payload captured on an iOS 17.0 beta. The same SHA-256 appears across repos, and the provenance traces to a commercial app. **Not usable without Aaron's decision (D-6).**
- The still must be the exact video frame at the still-image time. The still time should sit well inside the clip: about 0.5 s or mid-clip, not near the start.
- Several device reports say the video's long side must be about **1920 px or less**. One: on iPhone 16 Pro with iOS 27.0, 1080×2340 failed and 720×1560 played, with a device log saying "High Quality Mode does not support resolution >= 4K". This conflicts with the brief's "native pixel size".

**Contested**

- 30 vs 60 fps, and H.264 vs HEVC. Most iOS 26 and 27 successes use HEVC at 60 fps, but one generator reports 30 fps working.
- iOS 27 extras reported by one source: a sideways still, and an audio track in the camera's own format.
- Whether iPad plays wallpaper motion at all.

**Main sources:** developer.apple.com/forums/thread/798044, WWDC16 session 501, the iOS 26.5 SDK headers, ExifTool's Apple and QuickTime tag tables, and the README and issue reports of pudding0503/live-photo-batch, BuddhaNag12/glitter-live, deluxebear/FaceLift, TouSC/Video2LivePhoto and davidpovarsky/live-photos. These were read for facts only; licences were noted and no code was used.
