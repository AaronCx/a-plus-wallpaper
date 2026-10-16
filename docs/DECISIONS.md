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

**Status:** partly decided.

- **Name: a+wallpaper.** Decided by Aaron, 2026-10-16.
- **Bundle ID:** proposed `com.aaroncx.apluswallpaper`, to match `com.aaroncx.aplusterminal`. Aaron to confirm before any App Store Connect work. The spike uses `com.aaroncx.apluswallpaper.spike` so it can't collide with the real app on a device.

### D-2: code licence

**Status:** open. The brief suggests MIT; community presets would be CC0-1.0. Until Aaron decides there is no `LICENSE` file, so the code is "all rights reserved". Shader headers point here.

### D-3: art browsing, curated or open search

**Status:** open. Blocks Phase 3. The brief recommends starting curated (lower age rating, see risk 5).

### D-4: community presets repo name

**Status:** open. Blocks Phase 4. A suggestion that follows this repo's naming is `a-plus-wallpaper-presets`.

### D-5: iOS 17 as the minimum

**Status:** open, assumed for now. The spike targets iOS 17.0, and every symbol it uses compiles at 17.0. Simulator results on iOS 17.5 are in the parameter tables below.

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

## Phase 0: exact parameters of each Live Photo variant

PARAMS_PLACEHOLDER

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
