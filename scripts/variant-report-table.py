#!/usr/bin/env python3
"""Print Markdown tables from the spike's per-variant JSON reports.

Usage: variant-report-table.py REPORT_DIR [REPORT_DIR ...]

Each REPORT_DIR holds the <variant>.json files that VariantMatrixTests writes
for one simulator. Prints one summary table per simulator: what was written,
and what Photos stored.
"""
import json
import sys
from pathlib import Path

ORDER = ["1.5s", "2.0s", "3.0s"]


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
        "| Variant | Frames | Still frame (s) | Codec | Video px | Target Mbit/s | Measured Mbit/s | MOV KB | HEIC KB "
        "| Still-image-time | Photos: Live? | Photos kept IDs + track? |",
        "|---|---|---|---|---|---|---|---|---|---|---|---|",
    ]
    for r in sorted(reports, key=sort_key):
        written = r["writtenMovie"]
        stored = r["library"]["storedMovie"]
        stored_still = r["library"]["storedStill"]
        sit = written.get("stillImageTime") or next(
            (t for t in written["timedMetadata"] if t["identifier"].endswith("still-image-time")), None)
        sit_text = f"{sit['numberValue']} @ {sit['startSeconds']:.3f}s" if sit else "missing"
        kept = (
            stored["contentIdentifier"] == written["contentIdentifier"]
            and stored_still["contentIdentifier"] == written["contentIdentifier"]
            and any(t["identifier"].endswith("still-image-time") for t in stored["timedMetadata"])
            and stored.get("metadataTrackReferencesVideo") == written.get("metadataTrackReferencesVideo")
        )
        lines.append(
            f"| {r['variantID']} | {r['frameCount']} | {r['stillFrameIndex']} ({r['stillTimeSeconds']:.3f}) "
            f"| {written['videoCodec']} | {written['width']}x{written['height']} "
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
    for path in paths:
        files = sorted(Path(path).glob("*.json"))
        if not files:
            print(f"(no reports in {path})\n")
            status = 1
            continue
        reports = [json.loads(f.read_text()) for f in files]
        print(table(reports))
        print()
        if len(reports) != 12:
            print(f"WARNING: {len(reports)} reports in {path}, expected 12\n")
            status = 1
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
