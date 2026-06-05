"""Inject a finished short-video + its SRT captions into a reusable CapCut draft.

The CapCut half of the Sirius pipeline. make-video.ps1 already produces a FINISHED
vertical mp4 (voice + ducked music mixed in) plus a voice-synced .srt (exact Notion
text). This tool drops that pair into ONE reused CapCut draft (default
``SIRIUS_SHORT_CNT``) as:

  * one VIDEO track  -> the mp4 (its embedded audio = voice+music plays as-is)
  * one TEXT  track  -> each SRT cue as an EDITABLE CapCut text layer (NOT baked)

The human then opens the draft in CapCut, fine-tunes the captions (font / size /
position / wording), and exports the final mp4. CapCut has no headless export API
(see thuban docs/architecture/CAPCUT_INTEGRATION_FEASIBILITY_v1.md); export stays
a human action.

Workflow (User 決定 2026-06-05): ONE project, reused. Each run REPLACES the draft
with the latest video + SRT -- "毎回その動画と字幕を差し替えるだけ". Previous manual
tweaks are intentionally discarded (each piece is exported before the next run).

Reference: thuban tools/content/build_capcut_draft.py (pycapcut, proven 2026-05-30).
This is a much simpler case -- a single pre-rendered clip, not a multi-track EDL.

Usage (run with the same `py` used for nsfw-scan; needs `pip install pycapcut`):
    py tools/build-capcut-draft.py                       # newest *_字幕なし.mp4 in OutDir + its .srt
    py tools/build-capcut-draft.py --video C:\v_字幕なし.mp4   # derive .srt from the name
    py tools/build-capcut-draft.py --video V.mp4 --srt S.srt --name SIRIUS_SHORT_CNT
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import List, Optional, Tuple

import pycapcut as cc

# --- Sirius defaults (local, OneDrive) ---
DEFAULT_DRAFT_FOLDER = r"C:\Users\yuton\AppData\Local\CapCut\User Data\Projects\com.lveditor.draft"
DEFAULT_OUT_DIR = r"C:\Users\yuton\OneDrive\Desktop\自動生成動画"
DEFAULT_NAME = "SIRIUS_SHORT_CNT"   # the ONE reused Sirius CapCut project (User 2026-06-05)

NOCAP_SUFFIX = "_字幕なし.mp4"

_SRT_TIME = re.compile(
    r"(\d{2}):(\d{2}):(\d{2})[,.](\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2})[,.](\d{3})"
)


def _us(h: str, m: str, s: str, ms: str) -> int:
    return (int(h) * 3600 + int(m) * 60 + int(s)) * cc.SEC + int(ms) * 1000


def parse_srt(srt_path: Path) -> List[Tuple[int, int, str]]:
    """Parse an SRT into [(start_us, end_us, text)]. Split into blocks on blank
    lines; in each block the line with ``-->`` is the timing, everything after it
    is the text (the index line before it is ignored). Multi-line text is joined
    with a newline (CapCut keeps it as one editable text segment)."""
    raw = srt_path.read_text(encoding="utf-8-sig")  # tolerate a BOM if one slips in
    cues: List[Tuple[int, int, str]] = []
    for block in re.split(r"\r?\n[ \t]*\r?\n", raw.strip()):
        lines = block.splitlines()
        time_idx = start = end = None
        for i, ln in enumerate(lines):
            mt = _SRT_TIME.search(ln)
            if mt:
                time_idx = i
                start = _us(*mt.group(1, 2, 3, 4))
                end = _us(*mt.group(5, 6, 7, 8))
                break
        if time_idx is None:
            continue
        text = "\n".join(lines[time_idx + 1:]).strip()
        if text:
            cues.append((start, end, text))
    return cues


def _derive_srt(video: Path) -> Path:
    """`auto_<tag>_<stamp>_字幕なし.mp4` -> `auto_<tag>_<stamp>.srt`."""
    name = video.name
    stem = name[: -len(NOCAP_SUFFIX)] if name.endswith(NOCAP_SUFFIX) else video.stem
    return video.with_name(stem + ".srt")


def _newest_pair(out_dir: Path) -> Tuple[Path, Path]:
    vids = sorted(
        out_dir.glob("*" + NOCAP_SUFFIX), key=lambda p: p.stat().st_mtime, reverse=True
    )
    if not vids:
        raise SystemExit(f"[ERR] no '*{NOCAP_SUFFIX}' found in {out_dir}")
    video = vids[0]
    srt = _derive_srt(video)
    if not srt.exists():
        raise SystemExit(f"[ERR] matching SRT not found for {video.name}: {srt.name}")
    return video, srt


def build_draft(
    video: Path,
    srt: Path,
    draft_folder: Path,
    name: str,
    *,
    fps: int = 30,
    transform_y: float = 0.0,
    size: float = 10.0,
    border_width: float = 15.0,
    replace: bool = True,
) -> Path:
    cues = parse_srt(srt)
    if not cues:
        raise SystemExit(f"[ERR] no cues parsed from {srt}")

    material = cc.VideoMaterial(str(video))
    width, height, dur = material.width, material.height, material.duration

    folder = cc.DraftFolder(str(draft_folder))
    script = folder.create_draft(name, width, height, fps, allow_replace=replace)

    # 1) the finished clip (embedded voice+music plays as-is)
    script.add_track(cc.TrackType.video, track_name="video")
    script.add_segment(
        cc.VideoSegment(material, cc.Timerange(0, dur)), "video"
    )

    # 2) captions -> editable text layer (white fill + black outline, centred)
    script.add_track(cc.TrackType.text, track_name="captions")
    style = cc.TextStyle(
        size=size, color=(1.0, 1.0, 1.0), align=1, auto_wrapping=True
    )
    border = cc.TextBorder(alpha=1.0, color=(0.0, 0.0, 0.0), width=border_width)
    clip = cc.ClipSettings(transform_y=transform_y)
    for start, end, text in cues:
        end = min(end, dur)
        if end <= start:
            continue
        script.add_segment(
            cc.TextSegment(
                text,
                cc.Timerange(start, end - start),
                style=style,
                border=border,
                clip_settings=clip,
            ),
            "captions",
        )

    script.save()
    return draft_folder / name


def main(argv: Optional[List[str]] = None) -> int:
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8")  # type: ignore[attr-defined]
        except (AttributeError, ValueError):
            pass

    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--video", help=f"finished mp4 (default: newest *{NOCAP_SUFFIX} in --out-dir).")
    p.add_argument("--srt", help="SRT path (default: derived from the video name).")
    p.add_argument("--out-dir", default=DEFAULT_OUT_DIR, help="where make-video writes outputs.")
    p.add_argument("--draft-folder", default=DEFAULT_DRAFT_FOLDER, help="CapCut Drafts folder.")
    p.add_argument("--name", default=DEFAULT_NAME, help="reused CapCut draft (project) name.")
    p.add_argument("--fps", type=int, default=30)
    p.add_argument("--transform-y", type=float, default=0.0, help="caption vertical pos (+up/-down, 0=centre).")
    p.add_argument("--size", type=float, default=10.0, help="caption text size.")
    p.add_argument("--no-replace", action="store_true", help="fail instead of overwriting the draft.")
    args = p.parse_args(argv)

    out_dir = Path(args.out_dir)
    if args.video:
        video = Path(args.video)
        srt = Path(args.srt) if args.srt else _derive_srt(video)
    else:
        video, srt = _newest_pair(out_dir)
        if args.srt:
            srt = Path(args.srt)

    if not video.exists():
        raise SystemExit(f"[ERR] video not found: {video}")
    if not srt.exists():
        raise SystemExit(f"[ERR] srt not found: {srt}")

    draft_folder = Path(args.draft_folder)
    if not draft_folder.exists():
        raise SystemExit(
            f"[ERR] CapCut draft folder not found: {draft_folder}\n"
            "      set it via --draft-folder (CapCut > 設定 > ドラフト保存先)."
        )

    cues = parse_srt(srt)
    path = build_draft(
        video, srt, draft_folder, args.name,
        fps=args.fps, transform_y=args.transform_y, size=args.size,
        replace=not args.no_replace,
    )
    print(f"[OK] CapCut draft '{args.name}': {len(cues)} captions")
    print(f"     video: {video.name}")
    print(f"     srt  : {srt.name}")
    print(f"     dir  : {path}")
    print("     -> ★人間アクション: CapCut で開く → 字幕を微調整 → 書き出し")
    return 0


if __name__ == "__main__":
    sys.exit(main())
