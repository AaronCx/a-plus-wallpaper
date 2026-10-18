#!/usr/bin/env python3
"""Print Markdown tables from the spike's per-variant JSON reports.

Usage: variant-report-table.py REPORT_DIR [REPORT_DIR ...]

Each REPORT_DIR holds the <variant>.json files that VariantMatrixTests writes
for one simulator. Prints the parameters every variant shares (from the recipe
snapshot in the reports), then one table per simulator: what was written, and
what Photos stored.
"""
import json
import sys
from pathlib import Path

STILL_TIME = "still-image-time"
TRANSFORM = "live-photo-still-image-transform"
DIMENSIONS = "live-photo-still-image-transform-reference-dimensions"


def timed(movie, suffix):
    return next((t for t in movie["timedMetadata"] if (t.get("identifier") or "").endswith("/com.apple.quicktime." + suffix)), None)


def common(report):
    recipe = report["recipe"]
    track = recipe["stillImageTimeTrack"]
    return "\n".join([
        "Shared by every variant (recipe schema %d):" % recipe["schemaVersion"],
        "",
        "- Shader `spikeDrift`, seed %d, rendered at the screen's native pixel size, BGRA 8-bit, sRGB." % recipe["seed"],
        "- Still: HEIC, quality %g, maker-note key \"17\" = content identifier; the exact frame at the still time (frame index = floor(frames x %g))."
        % (recipe["still"]["compressionQuality"], recipe["still"]["timeFraction"]),
        "- Movie: QuickTime `.mov`, timescale 600, constant frame rate, no audio; top-level `com.apple.quicktime.content.identifier` (UTF-8).",
        "- Video: HEVC Main AutoLevel (`hvc1`) or H.264 High AutoLevel (`avc1`); BT.709 primaries, transfer and matrix; key frame every %gs; frame reordering %s; average bit rate = bits-per-pixel x width x height x fps with bits-per-pixel %s."
        % (recipe["video"]["keyFrameIntervalSeconds"], "on" if recipe["video"]["allowFrameReordering"] else "off",
           ", ".join("%s %g" % kv for kv in sorted(recipe["video"]["bitsPerPixel"].items()))),
        "- Timed metadata: one `mebx` track, one sample of %d tick(s) at the still time: `still-image-time` (int8) = %d%s%s."
        % (track["durationTicks"], track["value"],
           ", identity `live-photo-still-image-transform` (3x3 float64) and `...reference-dimensions` (float32, the video size)" if track["includeStillImageTransform"] else "",
           "; the track references the video track (`tref cdsc`)" if track["associateWithVideoTrack"] else ""),
        "- Saved with one `PHAssetCreationRequest`: `.photo` (HEIC) + `.pairedVideo` (MOV).",
    ])


def sort_key(report):
    return (report["durationSeconds"], report["framesPerSecond"], report["codec"])


def mbps(bits):
    return f"{bits / 1e6:.1f}" if bits else "?"


def table(reports):
    first = reports[0]
    device = first["device"]
    lines = [
        f"**{device['modelIdentifier']}, {device['systemName']} {device['systemVersion']}, "
        f"native {device['nativePixelSize']['width']}x{device['nativePixelSize']['height']} "
        f"@{device['nativeScale']:g}x**",
        "",
        "| Variant | Frames | Still frame (s) | Codec | Video px | Key frame every | Target Mbit/s | Measured Mbit/s "
        "| MOV KB | HEIC KB | Still sample | Photos: Live? | Photos kept IDs + metadata? |",
        "|---|---|---|---|---|---|---|---|---|---|---|---|---|",
    ]
    for r in sorted(reports, key=sort_key):
        written = r["writtenMovie"]
        stored = r["library"]["storedMovie"]
        stored_still = r["library"]["storedStill"]
        sit = timed(written, STILL_TIME)
        extras = [name for name, key in (("transform", TRANSFORM), ("dims", DIMENSIONS)) if timed(written, key)]
        if written.get("metadataTrackReferencesVideo"):
            extras.append("cdsc")
        sit_text = (f"{sit['numberValue']} @ {sit['startSeconds']:.3f}s for {round(sit['durationSeconds'] * 600)} tick"
                    + (f" + {', '.join(extras)}" if extras else "")) if sit else "missing"
        kept = (
            stored["contentIdentifier"] == written["contentIdentifier"]
            and stored_still["contentIdentifier"] == written["contentIdentifier"]
            and all((timed(stored, k) or {}).get("startSeconds") == (timed(written, k) or {}).get("startSeconds")
                    for k in (STILL_TIME, TRANSFORM, DIMENSIONS))
            and stored.get("metadataTrackReferencesVideo") == written.get("metadataTrackReferencesVideo")
        )
        lines.append(
            f"| {r['variantID']} | {r['frameCount']} | {r['stillFrameIndex']} ({r['stillTimeSeconds']:.3f}) "
            f"| {written['videoCodec']} | {written['width']}x{written['height']} | {r['keyFrameIntervalFrames']} frames "
            f"| {mbps(r['targetAverageBitRate'])} | {mbps(written.get('estimatedDataRate'))} "
            f"| {written['fileBytes'] // 1024} | {r['writtenStill']['fileBytes'] // 1024} "
            f"| {sit_text} | {'yes' if r['library']['isLivePhoto'] else 'NO'} | {'yes' if kept else 'NO'} |"
        )
    return "\n".join(lines)


def main(paths):
    if not paths:
        print(__doc__)
        return 64
    status = 0
    printed_common = False
    for path in paths:
        files = sorted(Path(path).glob("*.json"))
        if not files:
            print(f"(no reports in {path})\n")
            status = 1
            continue
        reports = [json.loads(f.read_text()) for f in files]
        if not printed_common:
            print(common(reports[0]))
            print()
            printed_common = True
        print(table(reports))
        print()
        if len(reports) != 12:
            print(f"WARNING: {len(reports)} reports in {path}, expected 12\n")
            status = 1
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
