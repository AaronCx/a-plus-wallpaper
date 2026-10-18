# a+wallpaper

A free, open-source, on-device wallpaper studio for iPhone and iPad.

No ads, subscriptions, in-app purchases, accounts, analytics or backend. Wallpapers come from original Metal shaders rendered on the device, community presets, public-domain museum art, or your own photos. iOS doesn't let apps set wallpapers, so you save the result and set it in Settings.

## Status

**Phase 0: Live Photo spike.** Before building the app, we check the riskiest assumption: will iOS use a Live Photo generated on the device as a moving Lock Screen wallpaper? The throwaway spike in [`Spike/`](Spike) renders an original shader and saves 12 Live Photo variants (duration × frame rate × codec) for testing on real devices. See [`docs/BRIEF.md`](docs/BRIEF.md) for the full plan and [`docs/DECISIONS.md`](docs/DECISIONS.md) for what has been decided.

## Building the spike

Requirements: Xcode 26.5 or later. No third-party dependencies.

```sh
open Spike/LivePhotoSpike.xcodeproj          # run the "LivePhotoSpike" scheme
scripts/spike-test.sh --device "iPhone 17"   # build, then run every test on a dedicated simulator
```

`scripts/spike-test.sh` creates its own simulator named `APW <device> (<iOS>)` so it never changes an existing one. It grants the spike Photos access, and it fails on any failed **or skipped** test.

## Project documents

| File | What it holds |
|------|---------------|
| [`docs/BRIEF.md`](docs/BRIEF.md) | The product brief and phase plan |
| [`docs/DECISIONS.md`](docs/DECISIONS.md) | Decisions made and decisions still open |
| [`docs/RISKS.md`](docs/RISKS.md) | Risk register |
| [`docs/HANDOFF.md`](docs/HANDOFF.md) | State at the end of the last session |

## License

Not chosen yet (see [`docs/DECISIONS.md`](docs/DECISIONS.md), D-2). Until a license is added, all rights are reserved.
