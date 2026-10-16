# Brief: Wallpaper Studio (working name)

A free, open-source, on-device wallpaper studio for iPhone and iPad.

- **For:** Claude Code on the Mac mini
- **Owner:** Aaron. Aaron merges every PR and does every GitHub-settings, App Store, signing and physical-device step.
- **Save this file as:** `docs/BRIEF.md` in the new repo. Read it at the start of every session.

---

## 1. What we're building

A wallpaper creator and explorer with **no ads, no subscriptions, no in-app purchases, no accounts, no analytics and no backend**. It must cost nothing to operate at any number of users.

Three ways to get a wallpaper:

1. **Generate:** original Metal shaders driven by a seed and a few parameters, rendered on the device.
2. **Explore:** community presets (tiny JSON files that reference shaders bundled in the app) plus public-domain art fetched directly from museum APIs.
3. **Your photos:** import through the system photo picker, then frame and crop for the device.

Output is either a static image at the device's exact native resolution, or a Live Photo for a moving Lock Screen. The user sets it in Settings, because iOS does not let apps set wallpapers.

Runs on every iPhone and iPad that supports iOS 17. iPhone Duo gets extras (fold-aware export, crease guide) that never appear on other devices.

### Non-goals (do not build)

- No server, database, cloud function or account system of any kind.
- No ads, IAP, tip jar or paywall. (A donation link in the README is Aaron's call, not yours.)
- No analytics and no third-party crash or telemetry SDKs.
- No downloading or compiling shader code at runtime.
- No hosting of images anywhere by us.
- No "8K" or "120fps" claims anywhere in the UI, README or store metadata.

---

## 2. Operating rules for this agent

### Process

- **One phase per session.** Branch `phase-N-short-name` off `main`. Open a PR with `gh` when the phase's Definition of Done is met. Never push to `main`, never force-push, never merge your own PR.
- **Start of session:** read `docs/BRIEF.md`, `docs/DECISIONS.md`, `docs/RISKS.md`, `docs/HANDOFF.md`. Run `xcodebuild -version` and note it.
- **End of session:** update `DECISIONS.md` and `RISKS.md`, and write `HANDOFF.md` (done, next, open questions, Xcode version used).
- Small commits with clear messages. Before every PR: clean build, zero warnings in our code, all tests green.
- **PR description:** what changed, how it was tested (which simulators and OS versions), which risks from section 7 it touches, and simulator screenshots for any UI change (`xcrun simctl io booted screenshot`).

### Stop and ask Aaron before

- Adding any third-party dependency. The default is zero. If one is approved: pin the exact version and record its license in `THIRD_PARTY_NOTICES.md`.
- Contacting any network host not on the allowlist in section 5.
- Anything that costs money, needs an account or needs an API key.
- Creating GitHub repos, changing repo settings, App Store Connect, TestFlight, signing identities or provisioning profiles.
- Any license question about code, shaders, images or fonts.
- Any spike result that contradicts this brief.

### Never

- Commit secrets, certificates (`.p12`, `.cer`), provisioning profiles or `.env` files. This project needs no secrets at all; add a `.gitignore` that covers them anyway.
- Copy shader code from Shadertoy, blogs, tutorials or other repos. Shadertoy's default license (CC BY-NC-SA 3.0) is incompatible with this project. Write original shaders and put "Original work, [license]" in each shader file's header.
- Guess at new APIs. For anything specific to iOS 26 or 27 (especially iPhone Duo hinge APIs), confirm exact symbol names in the installed SDK's headers or `.swiftinterface` files before writing code, and cite the header path in the PR.
- Run destructive commands outside the repo's working tree (deleting outside the repo, `simctl erase all`, keychain changes).
- Claim device performance from simulator numbers. Simulator GPU performance is meaningless.

---

## 3. Tech baseline

- Swift 6 language mode with complete strict concurrency. SwiftUI with Observation. UIKit only where needed (hosting `MTKView`, scene and screen access).
- **Deployment target iOS 17.0** (iPhone XS/XR and later). SwiftUI shader APIs and Live Photo wallpapers both require iOS 17.
- Universal app: iPhone and iPad.
- Rendering in Metal. **Each shader has one implementation used for both preview and export**, so the two can never drift apart.
- Build with the newest release Xcode installed on the Mac mini.

### Repo layout

```
App/                  SwiftUI app target, Info.plist, PrivacyInfo.xcprivacy, String Catalog
Packages/
  RenderCore/         Metal shaders, shader manifests, renderer (no UIKit)
  PresetKit/          preset schema, strict decoding, validation, clamping
  ArtSources/         museum API clients, rate limiting, public-domain filter, cache
  ExportKit/          static image and Live Photo writers, Photos saving
  DuoKit/             hinge, posture and fold features, availability-gated
Presets/seed/         presets bundled in the app (first launch and offline)
presets-repo/         contents for the future community presets repo (Phase 4)
Spike/                Phase 0 throwaway target
docs/                 BRIEF.md, DECISIONS.md, RISKS.md, HANDOFF.md,
                      privacy.md, support.md, review-notes.md
```

---

## 4. Phases

Each phase ends with a PR and a Definition of Done (DoD). Do not start a phase until the previous PR is merged.

### Phase 0: Spike the riskiest assumption (Live Photo export)

**Why first:** the moving-wallpaper feature depends on iOS accepting our generated Live Photo as a Lock Screen wallpaper with motion. The accepted parameters are not documented and have changed between iOS versions. If this fails, the product changes, so we find out before building anything else.

First create the repo skeleton: `.gitignore`, `docs/` files seeded from this brief (copy section 7 into `RISKS.md`, section 8 into `DECISIONS.md` as open items), and an empty `HANDOFF.md`.

Then build a throwaway `Spike/` target that:

1. Renders one simple original shader to frames offscreen at the current screen's native pixel size.
2. Writes a still (HEIC) and video (MOV) pair linked as a Live Photo: the same content identifier in the still's Apple maker-note and in the MOV's `com.apple.quicktime.content.identifier` metadata, plus a still-image-time timed metadata track. Save it with `PHAssetCreationRequest` using `.photo` and `.pairedVideo` resources. (This is the commonly documented approach. Verify it, don't assume it.)
3. Reads the asset back from Photos and asserts it loads as a `PHLivePhoto` (automated test).
4. Has a debug screen that saves variants Aaron can try as wallpapers: duration (1.5s, 2s, 3s) x frame rate (30, 60) x codec (HEVC, H.264).

**DoD:** round-trip test passes; every variant saves on the simulator; `DECISIONS.md` lists the exact parameters of each variant. **Then stop.** Aaron tests the variants on physical devices across iOS 17, 18, 26 and 27 and records which ones show motion. Phase 2's export settings come from his results.

### Phase 1: Render core

- 4 to 6 original shaders (for example: gradient mesh, flow field, noise terrain, geometric tiling, aurora).
- Each shader has a manifest: `id`, `version`, and parameters (`name`, `type`, `min`, `max`, `default`, `step`) plus a cost tier.
- **Deterministic:** a seeded PRNG implemented in the shader (a PCG-style hash from a 32-bit seed). Animation is driven by an explicit `t` parameter, never by wall-clock time.
- Renderer API along the lines of `render(shader:params:seed:t:pixelSize:) -> MTLTexture` for offscreen work, plus an `MTKView`-based preview on the same code path.
- **Preview performance:** render the preview at reduced scale with an adaptive frame rate. Use `CADisplayLink.preferredFrameRateRange` and set `CADisableMinimumFrameDurationOnPhone` in Info.plist so ProMotion devices can reach 120Hz. Drop to 30fps or pause when `ProcessInfo.thermalState` is `.serious` or `.critical`, when Low Power Mode is on, or when Reduce Motion is enabled.
- **Protect the GPU:** clamp every parameter to its manifest range, cap shader loop counts with compile-time constants, reject NaN and infinity.
- **Tests:** same seed and params give identical output on the same device; comparisons across GPUs use a tolerance (mean absolute pixel difference under a threshold), never exact hashes. Unit tests for every clamp.

**DoD:** all shaders render in a bare preview screen on iPhone and iPad simulators; tests green.

### Phase 2: Editor and export

- Editor: pick a shader, randomize the seed, sliders generated from the manifest, palette picker.
- **Target size:** read from the current window scene's screen (`windowScene.screen`, `nativeBounds` and `nativeScale`), not `UIScreen.main`, which is deprecated. Never hardcode a device size table for ordinary devices.
- **Static export:** PNG or HEIC at exact native pixels. On iPad, export a square at the long edge so it covers both orientations; verify the crop on device and record the result in `DECISIONS.md`.
- **Live export:** use only the parameters that passed Phase 0 on hardware. Keep them in a data file so they can change without code changes.
- **Memory:** stream frames through `AVAssetWriter` with a `CVPixelBufferPool` and a Metal texture cache. Never hold all frames in memory. Test the largest screens (Pro Max, 13-inch iPad Pro).
- **Photos:** request `.addOnly` authorization only, with `NSPhotoLibraryAddUsageDescription`. Import uses `PHPickerViewController`, which needs no library permission.
- After saving, show a short "How to set it" sheet (Settings > Wallpaper), since the app cannot set it.

**DoD:** export works on every simulator in the test matrix; memory stays flat during Live export (attach an Instruments Allocations capture to the PR).

### Phase 3: Public-domain art

**Prerequisite:** Aaron's decision on curated vs open search (section 8, item 3).

- **Sources:** Art Institute of Chicago (`api.artic.edu` plus its IIIF image server), The Met (`collectionapi.metmuseum.org`), Cleveland Museum of Art (`openaccess-api.clevelandart.org`). All are keyless. Requests go straight from the user's device to the museum.
- Put sources behind an `ArtSource` protocol so any one can be disabled with a one-line change if it breaks or changes terms.
- **Public-domain filter, enforced in exactly one place:** AIC `is_public_domain == true`; Met `isPublicDomain == true`; Cleveland `share_license_status == "CC0"`. Anything else is never displayed. Unit-tested against recorded fixtures for each source.
- **Attribution:** show title, artist, date, museum and credit line on every art detail view and in the export sheet. No museum logos.
- **Rate limiting:** a token bucket per host, well under published limits (AIC throttles anonymous requests at 60 per minute per IP; the Met asks callers to stay under 80 requests per second). Exponential backoff with jitter on 429 and 5xx. Send a descriptive User-Agent (app name and repo URL), and check AIC's docs for any identification header they request.
- **Resolution:** wallpapers need source images at least as large as the target screen. Check the available size (AIC IIIF `info.json`, Met image dimensions) and hide or clearly flag images that would be noticeably upscaled. Read each source's guidance on image request sizes before choosing them.
- **Cache:** `URLCache` plus an on-disk LRU with a size cap (about 200 MB, user-clearable in Settings). A clear offline state.
- **Tests** use recorded JSON fixtures served through a `URLProtocol` stub. No live network in tests.

**DoD:** browse, search, detail and export all work and degrade gracefully offline; the public-domain filter has tests for every source.

### Phase 4: Explore (community presets)

- **Preset format v1** (JSON, 8 KB max): `schema`, `id`, `name`, `author` (GitHub handle), `shader` (bundled id plus major version), `params`, `seed`, `palette`, `license` (`"CC0-1.0"`).
- **Presets are data only.** They can only reference shaders bundled in the app: no code, no URLs, no markup. Unknown shader ids or schema versions are skipped, never crashed on.
- **Decoding:** ignore unknown fields for forward compatibility, but strictly validate known ones. Clamp params to the manifest. Length-limit `name` and `author`, strip control characters, render all community text as plain text.
- **Distribution:** an `index.json` listing every preset with its SHA-256. The app fetches the index and presets from jsDelivr's GitHub CDN pinned to a release tag, falling back to `raw.githubusercontent.com`. Verify every preset's hash against the index before use. Check jsDelivr's current caching rules and document the chosen URL scheme in `DECISIONS.md`.
- Bundle a snapshot of presets in `Presets/seed/` so first launch and offline use work.
- **Thumbnails are rendered on the device** and cached. We host zero images.
- Prepare the community repo's contents in `presets-repo/`: README, CONTRIBUTING (CC0 plus DCO sign-off), JSON Schema, a GitHub Actions workflow that validates schema, size and hashes and regenerates `index.json`, and a CODEOWNERS file that requires Aaron's review. **Do not create the GitHub repo.** Aaron will.
- Fuzz the decoder with malformed, truncated and oversized inputs.

**DoD:** Explore works from the bundled seed and from a locally served index in tests; all malformed-preset tests pass.

### Phase 5: iPhone Duo extras

- **Toolchain:** the hinge APIs need the iOS 27.1 SDK (Xcode 27.1). If a release Xcode 27.1 is installed, gate the code with `#available(iOS 27.1, *)`. If only a beta is installed, put Duo code behind a Swift compilation condition (`DUO_SDK`) so `main` still builds with release Xcode, because App Store builds require release Xcode.
- **Verify symbols in the SDK first.** Third-party packages report `UIHingeInteraction`, hinge status and angle, and `reservedRegions(kind:)`. Treat those names as leads only.
- **Features:** crease guide overlay in the editor; a matched export pair for the inner and outer displays (read sizes from the screens at runtime where possible; any fallback table lives in one file with a source comment); an optional hinge-angle parameter that affects the live preview only, never the export. Drive layout from posture and size classes, and effects from the raw angle.
- On every other device, none of this is visible or loaded.

**DoD:** verified on the Duo simulator in every posture and during fold transitions; non-Duo layouts unchanged (compare snapshots before and after).

### Phase 6: Wallpaper of the day

- An App Intent, `GenerateWallpaperIntent` (random or chosen preset, current device size), that returns an image file so a Shortcuts automation can pass it to the built-in set-wallpaper action.
- Static images only. Render offscreen with no UI, finish quickly, keep memory low.
- Verify on device which iOS versions expose a Shortcuts set-wallpaper action that accepts an image, and document exact setup steps in the README and in the app.

**DoD:** the intent works from Shortcuts on the simulator; setup guide written.

### Phase 7: Release hardening

- `PrivacyInfo.xcprivacy`: tracking `false`, no collected data types, and the required-reason APIs actually used (for example `UserDefaults`). Generate Xcode's privacy report and attach it to the PR.
- App Store privacy label target is **Data Not Collected**. Confirm the code makes that true.
- `docs/privacy.md` and `docs/support.md`, ready for GitHub Pages (a privacy policy URL is required). The policy says plainly which hosts the app contacts and that, as with any web request, those servers see the device's IP address.
- Accessibility: VoiceOver labels on every control, Dynamic Type, Reduce Motion respected, sufficient contrast.
- All strings in a String Catalog; English only for v1.
- `docs/review-notes.md`: the generator is the core functionality, no login is needed, the list of network hosts, and how to test Live export.
- Draft store metadata with honest claims only.

**DoD:** archive builds with release Xcode and no warnings; a release checklist in the PR.

---

## 5. Network allowlist

All URLs are built in one `Endpoints.swift`. A unit test fails if any other host appears anywhere in the codebase.

- `api.artic.edu`, `www.artic.edu` (IIIF images)
- `collectionapi.metmuseum.org`, `images.metmuseum.org`
- `openaccess-api.clevelandart.org`, plus Cleveland's image host (confirm it from real API responses, then add it here in a PR)
- `cdn.jsdelivr.net`, `raw.githubusercontent.com` (presets only)

HTTPS only. No App Transport Security exceptions.

---

## 6. Test matrix

**Simulators, every PR:** the oldest supported iPhone on an iOS 17 runtime (if installed), iPhone SE (3rd gen), a current non-Pro iPhone, a Pro Max, an iPad (rotation, Split View and Stage Manager widths), and the iPhone Duo simulator from Phase 5 on. Latest iOS runtime for each, plus iOS 17 where available.

**Physical devices, Aaron:** wallpaper motion, thermals, real GPU performance, iPad wallpaper crop, Shortcuts wallpaper action.

---

## 7. Risk register

| # | Risk | Likelihood | Impact | Mitigation | Phase |
|---|------|-----------|--------|------------|-------|
| 1 | iOS won't animate our generated Live Photos as wallpapers, or the accepted parameters differ by iOS version | Med | High | Spike first; hardware matrix; parameters kept in data, not code | 0 |
| 2 | App Review rejects as spam or minimum functionality (saturated wallpaper category) | Med | High | Generator is the core, not a catalog; clear review notes; honest metadata | All |
| 3 | Displaying art that isn't public domain | Low | High | One enforced filter, fixture tests, attribution | 3 |
| 4 | Shader license contamination | Med | High | Original shaders only, header notes, no copying | 1 |
| 5 | Artistic nudity in museum collections affects age rating | High | Med | Aaron decides curated vs open; answer the rating questionnaire accurately | 3 |
| 6 | Downloaded content treated as executable code, or crafted to hang the GPU | Low | High | Presets are data only, bundled shaders, clamps, hash checks | 4 |
| 7 | Museum API changes, throttling or outages | Med | Med | Per-host limiter, backoff, cache, offline state, sources behind a protocol | 3 |
| 8 | Low-resolution source images look bad as wallpapers | High | Med | Size check; hide or flag | 3 |
| 9 | Heat and battery drain on older devices | Med | Med | Reduced-scale preview, adaptive fps, thermal state, Low Power Mode | 1 |
| 10 | Memory spikes exporting on the largest screens | Med | High | Streaming writer, buffer pools, Instruments check | 2 |
| 11 | Duo API names differ from reports, or SDK only in beta | Med | Med | Verify headers; `DUO_SDK` compile flag | 5 |
| 12 | Hosting costs appear | Low | Med | We host no images; presets are KB; CDN plus fallback | 4 |
| 13 | Offensive or malicious community submissions | Med | Med | PR review, CI validation, plain-text rendering, length limits | 4 |
| 14 | Privacy label turns out inaccurate | Low | High | No SDKs, allowlist test, privacy report | 7 |
| 15 | Supply-chain compromise | Low | High | Zero dependencies by default; pin anything approved | All |
| 16 | Scope creep, or one session burning the weekly usage limit | Med | Med | One phase per session, DoD, handoff notes | All |

---

## 8. Decisions needed from Aaron

Record each answer in `DECISIONS.md`. Don't block Phase 0 on these except item 1 (a placeholder name and bundle ID are fine for the spike).

1. App name and bundle ID.
2. Code license (MIT suggested) and confirm CC0 for community presets.
3. Art browsing: curated departments by default (lower age rating) or open search. Recommendation: curated first.
4. Name of the community presets repo.
5. Confirm iOS 17 as the minimum.

---

## 9. This session

Do **Phase 0 only**: repo skeleton, `docs/` files, `.gitignore`, then the spike. Open the PR, write `HANDOFF.md`, and stop.
