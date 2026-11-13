#!/usr/bin/env python3
"""End-to-end test for the HTTP MCP transport (raw JSON-RPC over HTTP).

Starts `docmunch mcp --http`, then drives it with urllib. No MCP SDK involved.

Usage: python tools/mcp_http_e2e.py [--port 18998]
Exit code 0 = all assertions passed.
"""

import json
import os
from concurrent.futures import ThreadPoolExecutor
import pathlib
import subprocess
import sys
import time
import urllib.error
import urllib.request

EXE = pathlib.Path("_build/native/debug/build/cmd/main") / ("main.exe" if os.name == "nt" else "main")
ROOT = ".doc-index-mcp-http"
PROTOCOL = "2026-07-28"


def post(url, method, params, rid):
    body = dict(params or {})
    body.setdefault(
        "_meta",
        {
            "io.modelcontextprotocol/protocolVersion": PROTOCOL,
            "io.modelcontextprotocol/clientCapabilities": {},
            "io.modelcontextprotocol/clientInfo": {"name": "docmunch-http-e2e", "version": "0"},
        },
    )
    payload = json.dumps({"jsonrpc": "2.0", "id": rid, "method": method, "params": body}).encode()
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream",
        "MCP-Protocol-Version": PROTOCOL,
        "Mcp-Method": method,
    }
    if method in ("tools/call", "prompts/get", "resources/read"):
        headers["Mcp-Name"] = (params or {}).get("name", "")
    req = urllib.request.Request(url, data=payload, method="POST", headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            ctype = resp.headers.get("Content-Type", "")
            raw = resp.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")
        raise RuntimeError(f"HTTP {exc.code} for {method}: {detail[:400]}") from exc
    if "text/event-stream" in ctype:
        for line in raw.splitlines():
            if line.startswith("data:"):
                return json.loads(line[5:].strip())
        raise RuntimeError(f"no data event in SSE response: {raw[:200]}")
    return json.loads(raw)


def tool_text(result):
    return "".join(
        b.get("text", "") for b in result.get("content", []) if b.get("type") == "text"
    )


def wait_for_port(url, timeout=15.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            urllib.request.urlopen(urllib.request.Request(url, method="POST", data=b"{}"), timeout=1)
            return True
        except urllib.error.HTTPError:
            return True  # server is up, just rejected the empty body
        except Exception:
            time.sleep(0.2)
    return False


def main() -> int:
    port = 18998
    if "--port" in sys.argv:
        port = int(sys.argv[sys.argv.index("--port") + 1])
    if not EXE.exists():
        print(f"missing {EXE}; run `moon build --target native`")
        return 2

    url = f"http://127.0.0.1:{port}/mcp"
    proc = subprocess.Popen(
        [str(EXE), "mcp", "--http", "--port", str(port), "--root", ROOT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
    )
    failures = []

    def check(name, cond, detail=""):
        if cond:
            print(f"ok   {name}")
        else:
            failures.append(name)
            print(f"FAIL {name} {detail}")

    try:
        if not wait_for_port(url):
            print("server did not open the port")
            return 1

        disc = post(url, "server/discover", {}, 1)
        check("server/discover", "supportedVersions" in disc.get("result", {}), str(disc)[:200])

        tools = post(url, "tools/list", {}, 2)["result"]
        names = sorted(t["name"] for t in tools.get("tools", []))
        check("tools/list has 12 tools", len(names) == 12, str(names))

        repo = "http-e2e"
        idx = post(
            url,
            "tools/call",
            {
                "name": "index_local",
                "arguments": {"path": "fixtures/markdown/readability-readme.md", "repo": repo},
            },
            3,
        )["result"]
        check("index_local", '"sections":8' in tool_text(idx), tool_text(idx)[:160])

        hits = post(
            url,
            "tools/call",
            {"name": "search_sections", "arguments": {"repo": repo, "query": "installation"}},
            4,
        )["result"]
        found = json.loads(tool_text(hits)).get("hits", [])
        check("search_sections", len(found) >= 1, str(found)[:160])

        got = post(
            url,
            "tools/call",
            {
                "name": "get_section",
                "arguments": {"repo": repo, "id": found[0]["id"], "verify": True},
            },
            5,
        )["result"]
        payload = json.loads(tool_text(got))
        check("get_section verified", payload.get("verified") is True, str(payload)[:120])

        # Concurrent index writes must not lose updates (shared mutex, D44).
        repo2 = "http-concurrent"
        fixtures = [
            "fixtures/markdown/arxiv-hichunk.md",
            "fixtures/markdown/python-asyncio.md",
        ]
        with ThreadPoolExecutor(max_workers=2) as pool:
            futures = [
                pool.submit(
                    post,
                    url,
                    "tools/call",
                    {"name": "index_local", "arguments": {"path": path, "repo": repo2}},
                    100 + i,
                )
                for i, path in enumerate(fixtures)
            ]
            for future in futures:
                future.result()
        toc2 = post(
            url, "tools/call", {"name": "get_toc", "arguments": {"repo": repo2}}, 110
        )["result"]
        seen = {s.get("path") for s in json.loads(tool_text(toc2)).get("sections", [])}
        check(
            "concurrent indexing keeps both docs",
            all(p in seen for p in fixtures),
            str(seen),
        )
        post(url, "tools/call", {"name": "delete_index", "arguments": {"repo": repo2}}, 111)

        deleted = post(
            url, "tools/call", {"name": "delete_index", "arguments": {"repo": repo}}, 6
        )["result"]
        check("delete_index", repo in tool_text(deleted), tool_text(deleted)[:120])
    except Exception as exc:  # noqa: BLE001 - e2e script reports the failure verbatim
        failures.append(str(exc))
        print(f"FAIL exception: {exc}")
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except Exception:
            proc.kill()

    if failures:
        print(f"\n{len(failures)} failure(s)")
        return 1
    print("\nall HTTP MCP e2e checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
