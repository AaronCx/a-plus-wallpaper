# Handoff

## Session 1: Phase 0, Live Photo spike (2026-10-16)

- **Toolchain:** Xcode 26.5 (17F42) on macOS 26 (M4 Mac mini). Simulator runtimes: iOS 26.5, 26.2 and 17.5 (17.5 was installed this session for the iOS 17 column of the test matrix).
- **Branch / PR:** `phase-0-live-photo-spike` → `main`.

### Done

- Created the GitHub repo `AaronCx/a-plus-wallpaper` (public, at Aaron's request). `main` holds only GitHub's initial commit; everything else is in the Phase 0 PR.
- Repo skeleton: `.gitignore` (covers certificates, profiles, keys and `.env`, though none are needed), `README.md`, and `docs/` with `BRIEF.md`, `DECISIONS.md` (section 8 as open items, plus new item D-6), `RISKS.md` (section 7 plus Phase 0 notes) and this file.
- The `Spike/LivePhotoSpike` throwaway app. No third-party code; Swift 6 with complete strict concurrency; warnings are errors; iOS 17.0 deployment target; iPhone and iPad.
  - **Rendering:** one original Metal compute shader (`SpikeDrift.metal`) renders offscreen at the window scene's native pixel size. Frames go straight into `CVPixelBuffer`s from the writer's pool through a Metal texture cache. Still and video share one code path.
  - **Writing:** a HEIC still (maker-note key 17) and a MOV with the content identifier and a still-image-time track. The track holds value -1, an identity still-image transform and reference dimensions, and references the video track (`tref cdsc`). These match camera files and use only public SDK identifiers.
  - **Saving:** `PHAssetCreationRequest` with `.photo` + `.pairedVideo`.
  - **Debug screen:** saves each of the 12 variants (1.5/2/3 s × 30/60 fps × HEVC/H.264), or all of them. Each frame carries a small label naming its variant, so a Lock Screen shows which one it is. It previews the last pair with `PHLivePhotoView` and can check each saved asset is stored as Live.
  - **Data, not code:** all export parameters live in `Spike/LivePhotoSpike/LivePhotoRecipe.json`.
- **Tests (Swift Testing, 11 tests, 12 parameterized variant cases):**
  - The recipe matrix.
  - Rendering: native size, same output for the same inputs, motion over time.
  - File format: identifiers, still-image-time value and time, transform, track reference, codec, size, frame count, duration.
  - Photos' own pairing check, and that it rejects mismatched pairs.
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

See the PR description and `DECISIONS.md` for the per-variant tables. All runs used `scripts/spike-matrix.sh`.

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

   **Fast path:** test the 12 variants on one iOS 26 device first. If none moves, the remaining iOS versions add little; go to D-6.
3. **Decide** D-6 (motion path) and D-1 to D-5 (bundle ID, licence, art browsing, presets repo name, iOS 17 minimum).

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
- **Simulator encoders are software only.** HEVC is slow (a full matrix run is about 4 minutes locally). The simulator's HEVC encoder (VCPHEVC) logs `unrecognised property key` once per movie; the Mac's encoder doesn't, and the output checks out (Main profile, `hvc1`, no reordering, BT.709 tags). It also encodes full-range YUV, while H.264 is video-range. Devices use the hardware encoder, so neither applies there.
- **Simulators created:** this session made dedicated `APW …` simulators. Remove them any time with `xcrun simctl delete <udid>`; `scripts/spike-test.sh` recreates them on demand.
- **Repo path:** the local repo lives at `~/Developer/github/a-plus-wallpaper`. `~/Developer/github/wallpaper-studio` is a symlink to it, kept so the original brief path still works.
