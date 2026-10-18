# Risk register

Copied from `docs/BRIEF.md`, section 7. Update this file at the end of every session. Phase notes below the table record what changed.

| # | Risk | Likelihood | Impact | Mitigation | Phase |
|---|------|-----------|--------|------------|-------|
| 1 | iOS won't animate our generated Live Photos as wallpapers, or the accepted parameters differ by iOS version | ~~Med~~ **High** (raised in Phase 0, see note) | High | Spike first; hardware matrix; parameters kept in data, not code | 0 |
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
| 17 | *(new, Phase 0)* The only known way to get Lock Screen motion relies on an undocumented, third-party binary payload | High | High | Not used. Decision D-6 is Aaron's (licence, provenance and App Review questions); see `DECISIONS.md` | 0, 2 |

## Phase 0 notes (2026-10-16)

**Risk 1 raised to High.** Research done before the hardware test points the same way from several directions. Details and sources are in `DECISIONS.md` under D-6.

- The brief's recipe is: maker-note key 17 in the still, `com.apple.quicktime.content.identifier` in the movie, and a still-image-time timed metadata track. It produces a valid Live Photo. Photos stores it as Live, and the spike's round-trip tests prove that on the simulator.
- The Lock Screen is a different matter. On iOS 17 to 18.1, an Apple Developer Forums report (thread 798044, August 2025) tried a matrix almost identical to ours and every variant showed "Motion Not Available". Apple DTS replied there that wallpaper eligibility depends on undocumented requirements, and advised against reverse-engineering them.
- Community generators that do get motion all add a `com.apple.quicktime.live-photo-info` timed metadata track. It has no public constant and an undocumented binary payload. Every working generator found copies the same 136-byte payload, which traces back to a commercial app.
- The simulator cannot answer the question. Its wallpaper editor never offers "Live Effect" for any photo, because the on-device ML step behind the "settling effect" fails in the simulator. Only Aaron's hardware test settles it.

**Mitigation still in place:** the tunable export parameters live in `Spike/LivePhotoSpike/LivePhotoRecipe.json` (data, not code). Codec profile, colour tags and output size are still in code (see `HANDOFF.md`). The 12-variant hardware matrix is ready for Aaron.

**Risk 15 unchanged:** zero dependencies. The project file is hand-written so no generator tool is needed. CI uses only `actions/checkout`, pinned to a full commit SHA.
