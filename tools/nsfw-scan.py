#!/usr/bin/env python3
# nsfw-scan.py -- strict nudity gate for make-video.ps1.
#
# Scans image frames with NudeNet and flags exposed-nudity classes. Used to
# keep nude / exposed-genitalia footage out of generated videos.
#
# Usage:
#   py tools/nsfw-scan.py [--threshold 0.35] frame1.png frame2.png ...
#
# Prints one JSON line: {"unsafe": bool, "threshold": float, "hits": [...]}.
# Exit code: 0 = safe, 2 = unsafe (hits found), 1 = error.

import sys
import json

# Exposed-nudity classes we refuse. (COVERED_* classes are allowed.)
FLAG = {
    "FEMALE_GENITALIA_EXPOSED",
    "MALE_GENITALIA_EXPOSED",
    "ANUS_EXPOSED",
    "BUTTOCKS_EXPOSED",
    "FEMALE_BREAST_EXPOSED",
}


def main():
    args = sys.argv[1:]
    threshold = 0.35
    if len(args) >= 2 and args[0] == "--threshold":
        threshold = float(args[1])
        args = args[2:]
    if not args:
        print(json.dumps({"unsafe": False, "threshold": threshold, "hits": [], "note": "no images"}))
        sys.exit(0)

    try:
        from nudenet import NudeDetector
        detector = NudeDetector()
    except Exception as e:  # detector unavailable -> caller decides (fail-closed)
        print(json.dumps({"error": f"detector init failed: {e}"}))
        sys.exit(1)

    hits = []
    alldet = {}
    for img in args:
        try:
            dets = detector.detect(img)
        except Exception as e:
            print(json.dumps({"error": f"detect failed for {img}: {e}"}))
            sys.exit(1)
        for d in dets:
            cls = d.get("class", "")
            score = float(d.get("score", 0))
            alldet.setdefault(cls, 0)
            alldet[cls] = max(alldet[cls], round(score, 3))
            if cls in FLAG and score >= threshold:
                hits.append({"image": img, "class": cls, "score": round(score, 3)})

    out = {"unsafe": len(hits) > 0, "threshold": threshold, "hits": hits, "seen": alldet}
    print(json.dumps(out, ensure_ascii=False))
    sys.exit(2 if hits else 0)


if __name__ == "__main__":
    main()
