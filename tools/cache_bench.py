#!/usr/bin/env python3
"""Does an in-process index cache actually remove the per-request index cost?

An MCP server lives for the whole session, so it should parse index.json once
per repo instead of once per request. This script measures that directly:

  * cold CLI call   - one process, one request (index parsed every time)
  * MCP first call  - server start + index parse
  * MCP later calls - cached index, so only scan + read_at remain

Usage: python tools/cache_bench.py [--copies 10] [--repeat 15]
Exit code 0 = every assertion passed.
"""

import json
import pathlib
import shutil
import statistics
import subprocess
import sys
import tempfile
import time

PROTOCOL = "2026-07-28"
DOCS = pathlib.Path("docs")
REPO = "bench"
META = {
    "io.modelcontextprotocol/protocolVersion": PROTOCOL,
    "io.modelcontextprotocol/clientCapabilities": {},
    "io.modelcontextprotocol/clientInfo": {"name": "cache-bench", "version": "0"},
}


def resolve_exe():
    base = pathlib.Path("_build/native/debug/build/cmd/main")
    for name in ("main.exe", "main"):
        if (base / name).exists():
            return base / name
    return base / "main.exe"


EXE = resolve_exe()
FAILURES = []


def check(name, cond, detail=""):
    if cond:
        print(f"ok   {name}")
    else:
        FAILURES.append(name)
        print(f"FAIL {name} {detail}")


class Client:
    def __init__(self, root):
        self.proc = subprocess.Popen(
            [str(EXE), "mcp", "--root", str(root)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            bufsize=1,
        )
        self.next_id = 1

    def call(self, method, params=None):
        payload = {
            "jsonrpc": "2.0",
            "id": self.next_id,
            "method": method,
            "params": {**(params or {}), "_meta": META},
        }
        self.next_id += 1
        assert self.proc.stdin is not None and self.proc.stdout is not None
        self.proc.stdin.write(json.dumps(payload) + "\n")
        self.proc.stdin.flush()
        start = time.perf_counter()
        while True:
            line = self.proc.stdout.readline()
            if not line:
                raise RuntimeError("server closed the pipe")
            line = line.strip()
            if not line:
                continue
            try:
                msg = json.loads(line)
            except json.JSONDecodeError:
                continue
            if msg.get("id") == payload["id"]:
                return msg, (time.perf_counter() - start) * 1000.0

    def close(self):
        try:
            if self.proc.stdin:
                self.proc.stdin.close()
            self.proc.wait(timeout=5)
        except Exception:
            self.proc.kill()


def build_corpus(src, copies):
    for i in range(copies):
        for path in src.glob("*.md"):
            target = path.parent / f"copy{i}" / path.name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(path.read_text(encoding="utf-8"), encoding="utf-8")


def cli_time(args, repeat=7):
    times = []
    for _ in range(repeat):
        start = time.perf_counter()
        subprocess.run([str(EXE), *args], capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
        times.append((time.perf_counter() - start) * 1000.0)
    return statistics.median(times)


def main():
    copies = 10
    repeat = 15
    if "--copies" in sys.argv:
        copies = int(sys.argv[sys.argv.index("--copies") + 1])
    if "--repeat" in sys.argv:
        repeat = int(sys.argv[sys.argv.index("--repeat") + 1])

    if not EXE.exists():
        print(f"missing {EXE}; run `moon build --target native`")
        return 2

    work = pathlib.Path(tempfile.mkdtemp(prefix="docmunch-cache-"))
    try:
        corpus = work / "src"
        corpus.mkdir()
        build_corpus(DOCS, copies)
        # build_corpus wrote copy dirs next to docs; move them together instead
        for d in DOCS.glob("copy*"):
            shutil.move(str(d), str(corpus / d.name))
        root = work / "idx"
        subprocess.run(
            [str(EXE), "index-dir", str(corpus), "--repo", REPO, "--root", str(root)],
            capture_output=True, text=True, encoding="utf-8", errors="replace",
        )

        index = json.loads((root / REPO / "index.json").read_text(encoding="utf-8"))
        sections = index["sections"]
        sample = sections[len(sections) // 2]

        cold_fetch = cli_time(["section", REPO, sample["id"], "--root", str(root)])
        cold_search = cli_time(["search", REPO, "索引 取回", "--root", str(root)])

        client = Client(root)
        try:
            client.call("server/discover")
            # First request pays server start + index parse.
            _, first_fetch = client.call(
                "tools/call", {"name": "get_section", "arguments": {"repo": REPO, "id": sample["id"]}}
            )
            warm_fetch = [
                client.call(
                    "tools/call",
                    {"name": "get_section", "arguments": {"repo": REPO, "id": sample["id"]}},
                )[1]
                for _ in range(repeat)
            ]
            _, first_search = client.call(
                "tools/call",
                {"name": "search_sections", "arguments": {"repo": REPO, "query": "索引 取回"}},
            )
            warm_search = [
                client.call(
                    "tools/call",
                    {"name": "search_sections", "arguments": {"repo": REPO, "query": "索引 取回"}},
                )[1]
                for _ in range(repeat)
            ]
        finally:
            client.close()

        warm_fetch_med = statistics.median(warm_fetch)
        warm_search_med = statistics.median(warm_search)

        print(f"\ncorpus: {copies} copies, {len(index['doc_paths'])} docs, "
              f"{len(sections)} sections, index "
              f"{(root / REPO / 'index.json').stat().st_size / 1024:.0f} KB\n")
        header = f"{'path':22} {'get_section':>13} {'search_sections':>16}"
        print(header)
        print("-" * len(header))
        print(f"{'cold CLI (parse each)':22} {cold_fetch:>11.1f} ms {cold_search:>14.1f} ms")
        print(f"{'MCP first call':22} {first_fetch:>11.1f} ms {first_search:>14.1f} ms")
        print(f"{'MCP cached (median)':22} {warm_fetch_med:>11.1f} ms {warm_search_med:>14.1f} ms")

        speedup_fetch = cold_fetch / max(warm_fetch_med, 0.01)
        speedup_search = cold_search / max(warm_search_med, 0.01)
        print(f"\nspeedup vs cold CLI: fetch {speedup_fetch:.1f}x, "
              f"search {speedup_search:.1f}x")

        check("cached fetch is faster than cold CLI", speedup_fetch > 2.0,
              f"{speedup_fetch:.2f}x")
        check("cached search is faster than cold CLI", speedup_search > 2.0,
              f"{speedup_search:.2f}x")
        check("first call includes the parse", first_fetch >= warm_fetch_med,
              f"first={first_fetch:.1f} warm={warm_fetch_med:.1f}")
    finally:
        shutil.rmtree(work, ignore_errors=True)

    if FAILURES:
        print(f"\n{len(FAILURES)} failure(s)")
        return 1
    print("\ncache bench passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
