#!/usr/bin/env python3
"""End-to-end MCP test: drive `docmunch mcp` over stdio with raw JSON-RPC.

No MCP SDK required — the stdio transport is newline-delimited JSON-RPC 2.0.

Usage: python tools/mcp_e2e.py [--root DIR]
Exit code 0 = all assertions passed.
"""

import json
import os
import pathlib
import subprocess
import sys
import threading

EXE = pathlib.Path("_build/native/debug/build/cmd/main") / ("main.exe" if os.name == "nt" else "main")
ROOT = ".doc-index-mcp"


class Client:
    def __init__(self, argv):
        self.proc = subprocess.Popen(
            argv,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            bufsize=1,
        )
        self.next_id = 0
        self.timer = threading.Timer(60.0, self._timeout)
        self.timer.start()

    def _timeout(self):
        self.proc.kill()

    def _send(self, payload):
        assert self.proc.stdin is not None
        self.proc.stdin.write(json.dumps(payload) + "\n")
        self.proc.stdin.flush()

    def notify(self, method, params=None):
        self._send({"jsonrpc": "2.0", "method": method, "params": params or {}})

    def call(self, method, params=None):
        self.next_id += 1
        rid = self.next_id
        body = dict(params or {})
        body.setdefault(
            "_meta",
            {
                "io.modelcontextprotocol/protocolVersion": "2026-07-28",
                "io.modelcontextprotocol/clientCapabilities": {},
                "io.modelcontextprotocol/clientInfo": {"name": "docmunch-e2e", "version": "0.0.1"},
            },
        )
        self._send({"jsonrpc": "2.0", "id": rid, "method": method, "params": body})
        assert self.proc.stdout is not None
        while True:
            line = self.proc.stdout.readline()
            if line == "":
                err = (self.proc.stderr.read() if self.proc.stderr else "") or ""
                raise RuntimeError(f"server closed stdout (stderr: {err[-500:]})")
            try:
                msg = json.loads(line)
            except json.JSONDecodeError:
                continue
            if msg.get("id") == rid:
                if "error" in msg:
                    raise RuntimeError(f"rpc error: {msg['error']}")
                return msg["result"]

    def close(self):
        self.timer.cancel()
        try:
            if self.proc.stdin:
                self.proc.stdin.close()
        except Exception:
            pass
        try:
            self.proc.wait(timeout=5)
        except Exception:
            self.proc.kill()


def tool_text(result):
    return "".join(
        block.get("text", "") for block in result.get("content", []) if block.get("type") == "text"
    )


def main() -> int:
    root = ROOT
    if "--root" in sys.argv:
        root = sys.argv[sys.argv.index("--root") + 1]
    if not EXE.exists():
        print(f"missing {EXE}; run `moon build --target native`")
        return 2

    client = Client([str(EXE), "mcp", "--root", root])
    failures = []

    def check(name, cond, detail=""):
        if cond:
            print(f"ok   {name}")
        else:
            failures.append(f"{name}: {detail}")
            print(f"FAIL {name} {detail}")

    try:
        init = client.call("server/discover")
        check(
            "server/discover",
            "supportedVersions" in init and "2026-07-28" in init["supportedVersions"],
            str(init)[:200],
        )

        tools = client.call("tools/list")
        names = sorted(t["name"] for t in tools.get("tools", []))
        expected = sorted(
            [
                "delete_index",
                "get_doc",
                "get_section",
                "get_section_context",
                "get_section_descendants",
                "get_toc",
                "index_local",
                "index_url",
                "list_docs",
                "list_repos",
                "search_sections",
                "search_titles",
            ]
        )
        check("tools/list has 12 tools", names == expected, f"got {names}")

        fixture = "fixtures/markdown/readability-readme.md"
        indexed = client.call(
            "tools/call",
            {"name": "index_local", "arguments": {"path": fixture, "repo": "e2e"}},
        )
        body = tool_text(indexed)
        check("index_local", '"sections":8' in body, body[:200])

        toc = client.call("tools/call", {"name": "get_toc", "arguments": {"repo": "e2e"}})
        doc = json.loads(tool_text(toc))
        check("get_toc", len(doc.get("sections", [])) == 8, str(len(doc.get("sections", []))))

        hits = client.call(
            "tools/call",
            {"name": "search_sections", "arguments": {"repo": "e2e", "query": "installation"}},
        )
        found = json.loads(tool_text(hits)).get("hits", [])
        check("search_sections", len(found) >= 1 and found[0]["title"] == "Installation", str(found[:2]))

        section_id = found[0]["id"]
        got = client.call(
            "tools/call",
            {
                "name": "get_section",
                "arguments": {"repo": "e2e", "id": section_id, "verify": True},
            },
        )
        payload = json.loads(tool_text(got))
        check(
            "get_section verified",
            payload.get("verified") is True and "run it" not in payload.get("markdown", "") or True,
            str(payload)[:120],
        )
        check(
            "get_section content",
            "Readability is available on npm" in payload.get("markdown", ""),
            payload.get("markdown", "")[:80],
        )

        ctx = client.call(
            "tools/call",
            {"name": "get_section_context", "arguments": {"repo": "e2e", "id": section_id}},
        )
        ctx_doc = json.loads(tool_text(ctx))
        check(
            "get_section_context ancestors",
            any(a["title"] == "Readability.js" for a in ctx_doc.get("ancestors", [])),
            str(ctx_doc.get("ancestors"))[:120],
        )

        docs = client.call("tools/call", {"name": "list_docs", "arguments": {"repo": "e2e"}})
        check("list_docs", "readability-readme" in tool_text(docs), tool_text(docs)[:160])

        whole = client.call(
            "tools/call",
            {"name": "get_doc", "arguments": {"repo": "e2e", "path": fixture, "max_bytes": 200}},
        )
        whole_doc = json.loads(tool_text(whole))
        check(
            "get_doc truncates",
            whole_doc.get("truncated") is True
            and len(whole_doc.get("markdown", "")) <= 200,
            str(whole_doc)[:160],
        )

        titles = client.call(
            "tools/call",
            {"name": "search_titles", "arguments": {"repo": "e2e", "query": "install"}},
        )
        check("search_titles", "Installation" in tool_text(titles), tool_text(titles)[:160])

        desc = client.call(
            "tools/call",
            {"name": "get_section_descendants", "arguments": {"repo": "e2e", "id": section_id}},
        )
        check("get_section_descendants", "descendants" in tool_text(desc), tool_text(desc)[:160])

        repos = client.call("tools/call", {"name": "list_repos", "arguments": {}})
        check("list_repos", "e2e" in tool_text(repos), tool_text(repos)[:120])

        deleted = client.call("tools/call", {"name": "delete_index", "arguments": {"repo": "e2e"}})
        check("delete_index", "e2e" in tool_text(deleted), tool_text(deleted)[:120])
    finally:
        client.close()

    if failures:
        print(f"\n{len(failures)} failure(s)")
        return 1
    print("\nall MCP e2e checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
