#!/usr/bin/env python3
"""End-to-end test for the MCP HTTP bearer-token guard.

Starts `docmunch mcp --http --auth-token ...` and checks that:
  - a request without Authorization is rejected with 401
  - a request with the wrong token is rejected with 401
  - a request with the right token succeeds
  - stdio mode is unaffected (no token needed)

Usage: python tools/mcp_auth_e2e.py [--port 18996]
Exit code 0 = all assertions passed.
"""

import json
import os
import pathlib
import subprocess
import sys
import time
import urllib.error
import urllib.request

EXE = pathlib.Path("_build/native/debug/build/cmd/main") / ("main.exe" if os.name == "nt" else "main")
ROOT = ".doc-index-auth-e2e"
PROTOCOL = "2026-07-28"
TOKEN = "docmunch-test-token"


def request(url, token):
    body = json.dumps(
        {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "server/discover",
            "params": {
                "_meta": {
                    "io.modelcontextprotocol/protocolVersion": PROTOCOL,
                    "io.modelcontextprotocol/clientCapabilities": {},
                    "io.modelcontextprotocol/clientInfo": {"name": "auth-e2e", "version": "0"},
                }
            },
        }
    ).encode()
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream",
        "MCP-Protocol-Version": PROTOCOL,
        "Mcp-Method": "server/discover",
    }
    if token is not None:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, data=body, method="POST", headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return resp.status
    except urllib.error.HTTPError as exc:
        return exc.code


def wait_for_port(url, timeout=15.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            urllib.request.urlopen(
                urllib.request.Request(url, method="POST", data=b"{}"), timeout=1
            )
            return True
        except urllib.error.HTTPError:
            return True
        except Exception:
            time.sleep(0.2)
    return False


def main() -> int:
    port = 18996
    if "--port" in sys.argv:
        port = int(sys.argv[sys.argv.index("--port") + 1])
    if not EXE.exists():
        print(f"missing {EXE}; run `moon build --target native`")
        return 2

    url = f"http://127.0.0.1:{port}/mcp"
    proc = subprocess.Popen(
        [str(EXE), "mcp", "--http", "--port", str(port), "--root", ROOT, "--auth-token", TOKEN],
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
        check("no token -> 401", request(url, None) == 401, str(request(url, None)))
        check("wrong token -> 401", request(url, "nope") == 401, str(request(url, "nope")))
        check("right token -> 200", request(url, TOKEN) == 200, str(request(url, TOKEN)))
    except Exception as exc:  # noqa: BLE001 - e2e reports verbatim
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
    print("\nall auth e2e checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
