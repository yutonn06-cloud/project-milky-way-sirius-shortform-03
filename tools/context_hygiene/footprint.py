r"""Auto-load footprint ledger — track the per-session context cost over time.

This is the measurement backbone for the ``context-hygiene`` skill. Compression
only matters if it actually shrinks what Claude reads every session, so this tool
turns that into a tracked number: it measures the *auto-load footprint* (the files
injected into context at every session start), appends a timestamped snapshot to a
git-tracked ledger, and renders a report showing the current state, the delta since
the last compression, and a visual trend.

What counts as auto-load footprint (the things that cost tokens *every* session):

- ``CLAUDE.md``                 — root bootstrap doc (satellite 起動文)
- ``.claude/CLAUDE.md``         — planet core / brain stem (budget: 5,000 tok)
- ``memory/MEMORY.md``          — auto-memory index (budget: 24,400 bytes)
- ``.claude/skills/*/SKILL.md`` — frontmatter descriptions, enumerated at startup

``MEMORY.md`` lives outside the repo, under the per-user Claude project dir
(``~/.claude/projects/<mangled-repo-path>/memory/MEMORY.md``). The mangled name is
the absolute repo path with ``: \ /`` replaced by ``-``; we derive it automatically
and fall back gracefully (or accept ``--memory-path``) if it is not found.

Token estimate: ``chars / 3.25`` (mixed JP/EN density). Byte counts are exact and
used for the MEMORY.md budget (which is a byte ceiling).

Ledger: a JSON array at ``docs/context_hygiene/footprint_ledger.json`` (tracked in
git so history survives). Each compression should end with a ``snapshot`` call so
the next report can show "how much did we save".

Usage (run as a script — install at tools/context_hygiene/footprint.py so that
``_REPO_ROOT`` = parents[2] resolves to the satellite root):
    python tools/context_hygiene/footprint.py snapshot --note "context-hygiene post-compression"
    python tools/context_hygiene/footprint.py report          # latest vs previous + trend, no write
    python tools/context_hygiene/footprint.py measure         # current numbers only, no ledger
    python tools/context_hygiene/footprint.py report --md      # markdown table report (for docs/)
"""
from __future__ import annotations

import argparse
import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional

_REPO_ROOT = Path(__file__).resolve().parents[2]
_LEDGER = _REPO_ROOT / "docs" / "context_hygiene" / "footprint_ledger.json"

# Budgets (see .claude/CLAUDE.md §0 / context-hygiene SKILL.md).
_MEMORY_BUDGET_BYTES = 24_400
_PLANET_CORE_BUDGET_TOKENS = 5_000
_CHARS_PER_TOKEN = 3.25

# Source labels (stable keys used in the ledger).
ROOT_CLAUDE = "root_claude_md"
PLANET_CORE = "planet_core"
MEMORY_INDEX = "memory_index"
SKILL_FRONTMATTER = "skill_frontmatter"

_LABELS = {
    ROOT_CLAUDE: "CLAUDE.md (root bootstrap)",
    PLANET_CORE: ".claude/CLAUDE.md (planet core)",
    MEMORY_INDEX: "memory/MEMORY.md (index)",
    SKILL_FRONTMATTER: "skill frontmatter ×N",
}


# --- pure helpers ------------------------------------------------------------

def est_tokens(chars: int) -> int:
    """Rough token estimate for mixed JP/EN text."""
    return round(chars / _CHARS_PER_TOKEN)


def derive_memory_path(repo_root: Path) -> Path:
    """Map the absolute repo path to its Claude auto-memory MEMORY.md.

    Claude Code mangles the project path by replacing ``: \\ /`` with ``-``.
    e.g. C:\\Users\\me\\projects\\foo  ->  C--Users-me-projects-foo
    """
    mangled = re.sub(r"[:\\/]", "-", str(repo_root))
    return Path.home() / ".claude" / "projects" / mangled / "memory" / "MEMORY.md"


def _file_metrics(path: Path) -> Optional[Dict[str, int]]:
    if not path or not path.exists():
        return None
    raw = path.read_text(encoding="utf-8")
    return {
        "bytes": path.stat().st_size,
        "chars": len(raw),
        "tokens": est_tokens(len(raw)),
    }


def _extract_frontmatter(raw: str) -> str:
    m = re.match(r"(?s)^---(.*?)---", raw)
    return m.group(1) if m else ""


def skill_frontmatter_metrics(skills_dir: Path) -> Dict[str, int]:
    """Aggregate frontmatter size across all .claude/skills/*/SKILL.md."""
    total_bytes = total_chars = count = 0
    if skills_dir.exists():
        for skill_md in sorted(skills_dir.glob("*/SKILL.md")):
            fm = _extract_frontmatter(skill_md.read_text(encoding="utf-8"))
            total_bytes += len(fm.encode("utf-8"))
            total_chars += len(fm)
            count += 1
    return {
        "bytes": total_bytes,
        "chars": total_chars,
        "tokens": est_tokens(total_chars),
        "count": count,
    }


def measure(repo_root: Path = _REPO_ROOT,
            memory_path: Optional[Path] = None) -> Dict[str, Any]:
    """Measure the current auto-load footprint. Pure read, no writes."""
    mem_path = memory_path or derive_memory_path(repo_root)
    sources: Dict[str, Any] = {
        ROOT_CLAUDE: _file_metrics(repo_root / "CLAUDE.md"),
        PLANET_CORE: _file_metrics(repo_root / ".claude" / "CLAUDE.md"),
        MEMORY_INDEX: _file_metrics(mem_path),
        SKILL_FRONTMATTER: skill_frontmatter_metrics(repo_root / ".claude" / "skills"),
    }
    total_bytes = sum(s["bytes"] for s in sources.values() if s)
    total_tokens = sum(s["tokens"] for s in sources.values() if s)

    mem = sources[MEMORY_INDEX]
    planet = sources[PLANET_CORE]
    budgets = {
        "memory_index_pct": round(mem["bytes"] / _MEMORY_BUDGET_BYTES * 100, 1) if mem else None,
        "planet_core_pct": round(planet["tokens"] / _PLANET_CORE_BUDGET_TOKENS * 100, 1) if planet else None,
    }
    return {
        "sources": sources,
        "totals": {"bytes": total_bytes, "tokens": total_tokens},
        "budgets": budgets,
        "memory_found": sources[MEMORY_INDEX] is not None,
        "memory_path": str(mem_path),
    }


def _delta(curr: Optional[float], prev: Optional[float]) -> Optional[float]:
    if curr is None or prev is None:
        return None
    return round(curr - prev, 1)


def _pct_change(curr: float, prev: float) -> Optional[float]:
    if not prev:
        return None
    return round((curr - prev) / prev * 100, 1)


# --- visual helpers ----------------------------------------------------------

_SPARK = "▁▂▃▄▅▆▇█"


def sparkline(values: List[float]) -> str:
    """Unicode sparkline; scaled to the (min,max) range of the series."""
    nums = [v for v in values if v is not None]
    if not nums:
        return ""
    lo, hi = min(nums), max(nums)
    span = hi - lo or 1.0
    out = []
    for v in values:
        if v is None:
            out.append(" ")
        else:
            idx = int((v - lo) / span * (len(_SPARK) - 1))
            out.append(_SPARK[idx])
    return "".join(out)


def gauge(pct: Optional[float], width: int = 24) -> str:
    if pct is None:
        return "[" + "?" * width + "]"
    filled = min(width, round(pct / 100 * width))
    return "[" + "█" * filled + "░" * (width - filled) + "]"


def _kb(b: int) -> str:
    return f"{b / 1024:.1f}KB"


def _fmt_signed(v: Optional[float], unit: str = "") -> str:
    if v is None:
        return "—"
    sign = "+" if v > 0 else ""
    return f"{sign}{v}{unit}"


# --- ledger ------------------------------------------------------------------

def load_ledger(path: Path = _LEDGER) -> List[Dict[str, Any]]:
    if not path.exists():
        return []
    return json.loads(path.read_text(encoding="utf-8"))


def save_ledger(entries: List[Dict[str, Any]], path: Path = _LEDGER) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(entries, ensure_ascii=False, indent=2) + "\n",
                    encoding="utf-8")


def make_snapshot(note: str, repo_root: Path = _REPO_ROOT,
                  memory_path: Optional[Path] = None,
                  now: Optional[datetime] = None) -> Dict[str, Any]:
    m = measure(repo_root, memory_path)
    ts = (now or datetime.now(timezone.utc)).isoformat(timespec="seconds")
    return {
        "timestamp": ts,
        "note": note,
        "sources": m["sources"],
        "totals": m["totals"],
        "budgets": m["budgets"],
    }


# --- report rendering --------------------------------------------------------

def render_report(entries: List[Dict[str, Any]], markdown: bool = False) -> str:
    if not entries:
        return "ledger is empty — run `snapshot` first."
    curr = entries[-1]
    prev = entries[-2] if len(entries) >= 2 else None
    first = entries[0]

    lines: List[str] = []
    h = "## " if markdown else ""
    lines.append(f"{h}Auto-load footprint — {curr['timestamp']}")
    lines.append(f"note: {curr['note']}")
    lines.append("")

    # Per-source table.
    if markdown:
        lines.append("| source | bytes | ~tokens | Δbytes vs prev | Δ% vs prev |")
        lines.append("|---|--:|--:|--:|--:|")
    else:
        lines.append(f"{'source':<34}{'bytes':>9}{'~tok':>8}{'Δbytes':>10}{'Δ%':>8}")
        lines.append("-" * 69)
    for key in (ROOT_CLAUDE, PLANET_CORE, MEMORY_INDEX, SKILL_FRONTMATTER):
        s = curr["sources"].get(key)
        if not s:
            continue
        ps = prev["sources"].get(key) if prev else None
        db = _delta(s["bytes"], ps["bytes"]) if ps else None
        dp = _pct_change(s["bytes"], ps["bytes"]) if ps else None
        label = _LABELS[key]
        if markdown:
            lines.append(f"| {label} | {s['bytes']:,} | {s['tokens']:,} | "
                         f"{_fmt_signed(db)} | {_fmt_signed(dp, '%')} |")
        else:
            lines.append(f"{label:<34}{s['bytes']:>9,}{s['tokens']:>8,}"
                         f"{_fmt_signed(db):>10}{_fmt_signed(dp, '%'):>8}")

    # Totals.
    t = curr["totals"]
    pt = prev["totals"] if prev else None
    dtb = _delta(t["bytes"], pt["bytes"]) if pt else None
    dtt = _delta(t["tokens"], pt["tokens"]) if pt else None
    if markdown:
        lines.append(f"| **TOTAL** | **{t['bytes']:,}** | **{t['tokens']:,}** | "
                     f"**{_fmt_signed(dtb)}** | — |")
    else:
        lines.append("-" * 69)
        lines.append(f"{'TOTAL':<34}{t['bytes']:>9,}{t['tokens']:>8,}"
                     f"{_fmt_signed(dtb):>10}{'':>8}")
    lines.append("")

    # Budget gauges (block/sparkline glyphs need monospace — fence in markdown).
    b = curr["budgets"]
    pb = prev["budgets"] if prev else None
    mem_pct = b.get("memory_index_pct")
    planet_pct = b.get("planet_core_pct")
    d_mem = _delta(mem_pct, pb.get("memory_index_pct")) if pb else None
    d_planet = _delta(planet_pct, pb.get("planet_core_pct")) if pb else None
    pre = "    " if not markdown else ""
    if markdown:
        lines.append("```text")
    lines.append(f"{pre}MEMORY.md   {gauge(mem_pct)} {mem_pct}% "
                 f"(budget 24.4KB, Δ {_fmt_signed(d_mem, 'pt')})")
    lines.append(f"{pre}planet core {gauge(planet_pct)} {planet_pct}% "
                 f"(budget 5,000 tok, Δ {_fmt_signed(d_planet, 'pt')})")
    lines.append("")

    # Trend (across all snapshots).
    if len(entries) >= 2:
        mem_series = [e["budgets"].get("memory_index_pct") for e in entries]
        tok_series = [e["totals"]["tokens"] for e in entries]
        lines.append(f"{pre}MEMORY.md %  {sparkline(mem_series)}  "
                     f"({mem_series[0]}% → {mem_series[-1]}%, {len(entries)} snapshots)")
        lines.append(f"{pre}total ~tok   {sparkline(tok_series)}  "
                     f"({tok_series[0]:,} → {tok_series[-1]:,})")
        lines.append("")
        # Cumulative since first.
        save_bytes = first["totals"]["bytes"] - t["bytes"]
        save_pct = _pct_change(t["bytes"], first["totals"]["bytes"])
        lines.append(f"{pre}since first snapshot: total {_fmt_signed(-save_bytes, ' bytes')} "
                     f"({_kb(abs(save_bytes))}), {_fmt_signed(save_pct, '%')}")

    if markdown:
        lines.append("```")

    return "\n".join(lines)


# --- CLI ---------------------------------------------------------------------

def main(argv: Optional[List[str]] = None) -> int:
    # The report uses block/sparkline glyphs; force UTF-8 on Windows consoles.
    try:
        import sys
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_snap = sub.add_parser("snapshot", help="measure + append to ledger + report")
    p_snap.add_argument("--note", required=True, help="what changed (e.g. compression date)")
    p_snap.add_argument("--memory-path", help="override MEMORY.md location")

    p_rep = sub.add_parser("report", help="render latest vs previous + trend (no write)")
    p_rep.add_argument("--md", action="store_true", help="markdown output")
    p_rep.add_argument("--out", help="write the report to this file (utf-8) instead of stdout")

    p_meas = sub.add_parser("measure", help="print current numbers only (no ledger)")
    p_meas.add_argument("--memory-path", help="override MEMORY.md location")

    args = ap.parse_args(argv)

    if args.cmd == "measure":
        mp = Path(args.memory_path) if args.memory_path else None
        m = measure(memory_path=mp)
        if not m["memory_found"]:
            print(f"[warn] MEMORY.md not found at {m['memory_path']}")
        print(json.dumps(m, ensure_ascii=False, indent=2))
        return 0

    if args.cmd == "snapshot":
        mp = Path(args.memory_path) if args.memory_path else None
        snap = make_snapshot(args.note, memory_path=mp)
        if snap["sources"][MEMORY_INDEX] is None:
            print(f"[warn] MEMORY.md not found — snapshot will omit it.")
        entries = load_ledger()
        entries.append(snap)
        save_ledger(entries)
        print(render_report(entries))
        print(f"\n[ledger] {len(entries)} snapshots -> {_LEDGER.relative_to(_REPO_ROOT)}")
        return 0

    if args.cmd == "report":
        text = render_report(load_ledger(), markdown=args.md)
        if args.out:
            out = Path(args.out)
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_text(text + "\n", encoding="utf-8")
            print(f"[report] written -> {args.out}")
        else:
            print(text)
        return 0

    return 1


if __name__ == "__main__":
    raise SystemExit(main())
