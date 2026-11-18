#!/usr/bin/env python3
"""Cost model: what does one retrieval actually cost, and what does it scale with?

The submission claimed "retrieval is O(1)". That was wrong, and this script
measures what the real shape is:

  cost = process start + load index (O(sections)) + locate section (O(sections))
       + read the section's byte range (O(section bytes), not document bytes)

It reports each term separately so the claim can be replaced with a measured
one instead of a slogan.

Usage: python tools/cost_model.py
"""

import json
import pathlib
import shutil
import statistics
import subprocess
import tempfile
import time

DOCS = pathlib.Path("docs")
REPO = "cost"


def resolve_exe():
    base = pathlib.Path("_build/native/debug/build/cmd/main")
    for name in ("main.exe", "main"):
        if (base / name).exists():
            return base / name
    return base / "main.exe"


EXE = resolve_exe()


def run(args, repeat=7):
    """Median wall time of a CLI call in ms, plus the last exit code and output."""
    times = []
    code, text = 0, ""
    for _ in range(repeat):
        start = time.perf_counter()
        proc = subprocess.run([str(EXE), *args], capture_output=True, text=True,
                              encoding="utf-8", errors="replace")
        times.append((time.perf_counter() - start) * 1000.0)
        code, text = proc.returncode, proc.stdout + proc.stderr
    return code, statistics.median(times), text


def build_corpus(root, copies):
    """Replicate docs/ `copies` times so section count scales."""
    for i in range(copies):
        for path in DOCS.glob("*.md"):
            target = root / f"c{i}" / path.name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(path.read_text(encoding="utf-8"), encoding="utf-8")


def main():
    if not EXE.exists():
        print(f"missing {EXE}")
        return 2

    work = pathlib.Path(tempfile.mkdtemp(prefix="docmunch-cost-"))
    try:
        rows = []
        for copies in (1, 5, 20):
            corpus = work / f"src{copies}"
            build_corpus(corpus, copies)
            root = work / f"idx{copies}"
            code, _, out = run(["index-dir", str(corpus), "--repo", REPO,
                                "--root", str(root)], repeat=1)
            if code != 0:
                print(out)
                return 1
            index_path = root / REPO / "index.json"
            index = json.loads(index_path.read_text(encoding="utf-8"))
            sections = index["sections"]
            sample = sections[len(sections) // 2]

            _, baseline_ms, _ = run(["repos", "--root", str(root)])
            _, search_ms, _ = run(["search", REPO, "索引 取回", "--root", str(root)])
            _, fetch_ms, _ = run(["section", REPO, sample["id"], "--root", str(root)])

            rows.append({
                "docs": len(index["doc_paths"]),
                "sections": len(sections),
                "index_kb": index_path.stat().st_size / 1024.0,
                "baseline_ms": baseline_ms,
                "search_ms": search_ms,
                "fetch_ms": fetch_ms,
                "section_bytes": sample["byte_end"] - sample["byte_start"],
                "doc_bytes": (corpus / "c0" / pathlib.Path(sample["doc_path"]).name)
                .stat().st_size if pathlib.Path(sample["doc_path"]).name in
                [p.name for p in (corpus / "c0").glob("*.md")] else 0,
            })

        header = (f"{'docs':>5} {'sections':>9} {'index KB':>9} {'startup ms':>11} "
                  f"{'search ms':>10} {'fetch ms':>9} {'section B':>10}")
        print("\n" + header)
        print("-" * len(header))
        for r in rows:
            print(f"{r['docs']:>5} {r['sections']:>9} {r['index_kb']:>9.1f} "
                  f"{r['baseline_ms']:>11.1f} {r['search_ms']:>10.1f} "
                  f"{r['fetch_ms']:>9.1f} {r['section_bytes']:>10}")

        print("\noperation cost (measured minus process startup):")
        for r in rows:
            print(f"  {r['sections']:>4} sections: search "
                  f"{r['search_ms'] - r['baseline_ms']:>6.1f} ms, fetch "
                  f"{r['fetch_ms'] - r['baseline_ms']:>6.1f} ms")

        # One large document: does fetching a section read the whole file?
        big = work / "big"
        big.mkdir()
        parts = []
        for i in range(50):
            parts.append(f"# Section {i}\n\n" + ("lorem ipsum dolor sit amet " * 400) + "\n")
        big_text = "\n".join(parts)
        (big / "huge.md").write_text(big_text, encoding="utf-8")
        big_root = work / "bigidx"
        run(["index-dir", str(big), "--repo", REPO, "--root", str(big_root)], repeat=1)
        big_index = json.loads((big_root / REPO / "index.json").read_text(encoding="utf-8"))
        mid = big_index["sections"][len(big_index["sections"]) // 2]
        _, one_doc_ms, _ = run(["section", REPO, mid["id"], "--root", str(big_root)])
        print(f"\nsingle {len(big_text) / 1024:.0f} KB document, "
              f"{len(big_index['sections'])} sections:")
        print(f"  fetch one section ({mid['byte_end'] - mid['byte_start']} B): "
              f"{one_doc_ms:.1f} ms")
        print(f"  section size / document size: "
              f"{(mid['byte_end'] - mid['byte_start']) / len(big_text):.4f}")
    finally:
        shutil.rmtree(work, ignore_errors=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
