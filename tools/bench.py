#!/usr/bin/env python3
"""End-to-end benchmark for the docmunch CLI (process-inclusive).

Reports:
  - index time per document, plus index/raw sizes
  - search latency (median of N runs)
  - section retrieval latency (median of N runs)
  - a `repos` baseline, which is roughly pure process startup

Usage: python tools/bench.py [--runs N]
"""

import os
import pathlib
import statistics
import subprocess
import sys
import time

EXE = pathlib.Path("_build/native/debug/build/cmd/main") / ("main.exe" if os.name == "nt" else "main")
ROOT = ".bench-index"
FIXTURES = sorted(pathlib.Path("fixtures/html").glob("*.html"))


def run(args, **kw):
    started = time.perf_counter()
    proc = subprocess.run([str(EXE), *args], capture_output=True, check=False, **kw)
    elapsed = (time.perf_counter() - started) * 1000.0
    return elapsed, proc


def main() -> int:
    runs = 15
    if "--runs" in sys.argv:
        runs = int(sys.argv[sys.argv.index("--runs") + 1])
    if not EXE.exists():
        print(f"missing {EXE}; run `moon build --target native`")
        return 2

    import shutil

    shutil.rmtree(ROOT, ignore_errors=True)

    print(f"{'fixture':34} {'index ms':>9} {'sections':>9} {'index B':>9} {'raw B':>9}")
    rows = []
    for html in FIXTURES:
        name = html.stem
        elapsed, proc = run(["index", str(html), "--repo", name, "--root", ROOT])
        out = proc.stdout.decode("utf-8", "replace")
        sections = out.split("sections=")[1].split()[0] if "sections=" in out else "?"
        idx = pathlib.Path(ROOT) / name / "index.json"
        raw_dir = pathlib.Path(ROOT) / name / "raw"
        raw_bytes = sum(p.stat().st_size for p in raw_dir.glob("*.bin")) if raw_dir.exists() else 0
        rows.append((name, elapsed, int(sections), idx.stat().st_size if idx.exists() else 0, raw_bytes))
        print(f"{name:34} {elapsed:9.1f} {sections:>9} {rows[-1][3]:9} {raw_bytes:9}")

    names = [r[0] for r in rows]
    name = "readability-readme" if "readability-readme" in names else names[0]
    _, base_proc = run(["repos", "--root", ROOT])
    base_times = []
    for _ in range(runs):
        t, _ = run(["repos", "--root", ROOT])
        base_times.append(t)

    search_times = []
    hit_id = None
    for _ in range(runs):
        t, proc = run(["search", name, "installation", "--root", ROOT])
        search_times.append(t)
        if hit_id is None:
            for line in proc.stdout.decode("utf-8", "replace").splitlines():
                if line.startswith("score="):
                    hit_id = line.split("id=")[1].split()[0]
                    break

    section_times = []
    if hit_id:
        for _ in range(runs):
            t, _ = run(["section", name, hit_id, "--root", ROOT])
            section_times.append(t)

    def med(xs):
        return statistics.median(xs) if xs else float("nan")

    print()
    print(f"process baseline (repos) : median {med(base_times):7.1f} ms")
    print(f"search                   : median {med(search_times):7.1f} ms")
    print(f"get_section              : median {med(section_times):7.1f} ms")
    if hit_id:
        print(f"section id used          : {hit_id}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
