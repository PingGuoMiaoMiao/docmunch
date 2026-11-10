#!/usr/bin/env python3
"""MoonBit hackathon acceptance checker (read-only).

Vendored copy of the `moonbit-hackathon-acceptance` skill script; keep the two
in sync. CI runs it as a self-check on every push.

Checks a submission against the rules MoonBit hackathon-style events publish:
MoonBit-primary code, public/traceable history, runnable README+tests,
substantial work in the round, OSI licence, explainable AI use.

Usage:
  python acceptance.py [--project DIR] [--since YYYY-MM-DD] [--skip-build] [--json]

Exit: 0 = no FAIL, 1 = at least one FAIL, 2 = bad invocation.
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

SKIP_DIRS = {".mooncakes", "_build", ".git", "node_modules", "target", ".dsh", ".agent-teams"}
OTHER_EXTS = {".py", ".js", ".ts", ".tsx", ".rs", ".go", ".c", ".cc", ".cpp", ".h", ".java", ".kt"}
OSI_RE = re.compile(r"(apache|mit license|mozilla public|bsd|isc license|unlicense|cc0|zlib|gpl|lgpl)", re.I)


def out(msg=""):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    print(msg)


def run(cmd, cwd, timeout=900):
    started = time.time()
    try:
        proc = subprocess.run(
            cmd, cwd=str(cwd), capture_output=True, text=True,
            encoding="utf-8", errors="replace", timeout=timeout,
        )
        return proc.returncode, (proc.stdout or "") + (proc.stderr or ""), time.time() - started
    except subprocess.TimeoutExpired:
        return 124, f"timeout after {timeout}s", timeout
    except FileNotFoundError:
        return 127, "command not found: " + " ".join(cmd), 0


def find_moon():
    found = shutil.which("moon")
    if found:
        return found
    fallback = Path.home() / ".moon" / "bin" / ("moon.exe" if os.name == "nt" else "moon")
    return str(fallback) if fallback.exists() else None


def read_text(path: Path, limit=20000) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace")[:limit]
    except OSError:
        return ""


def walk_sources(root: Path):
    mbt_files, mbt_lines, other_files, other_lines = 0, 0, 0, 0
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        ext = path.suffix.lower()
        if ext == ".mbt":
            mbt_files += 1
            try:
                mbt_lines += sum(1 for _ in path.open(encoding="utf-8", errors="replace"))
            except OSError:
                pass
        elif ext in OTHER_EXTS:
            other_files += 1
            try:
                other_lines += sum(1 for _ in path.open(encoding="utf-8", errors="replace"))
            except OSError:
                pass
    return mbt_files, mbt_lines, other_files, other_lines


def check_moonbit_primary(root: Path):
    mbt_files, mbt_lines, other_files, other_lines = walk_sources(root)
    if mbt_files == 0:
        return "FAIL", "no .mbt files found"
    if other_lines == 0 or mbt_lines >= other_lines * 3:
        return "PASS", f"{mbt_files} .mbt files / {mbt_lines} lines vs {other_files} other files / {other_lines} lines"
    return "WARN", f"MoonBit {mbt_lines} lines vs other languages {other_lines} lines — check the ratio"


def git(root: Path, *args):
    return run(["git", "-C", str(root), *args], cwd=root)


def check_history(root: Path, since: str):
    code, text, _ = git(root, "rev-parse", "--is-inside-work-tree")
    if code != 0 or "true" not in text.lower():
        return "FAIL", "not a git repository"
    _, log, _ = git(root, "log", "--oneline")
    commits = len([line for line in log.splitlines() if line.strip()])
    _, dirty, _ = git(root, "status", "--porcelain")
    dirty_count = len([line for line in dirty.splitlines() if line.strip()])
    window = commits
    if since:
        _, recent, _ = git(root, "log", "--oneline", f"--since={since}")
        window = len([line for line in recent.splitlines() if line.strip()])
    evidence = f"{commits} commits total, {window} since {since or 'start'}, {dirty_count} uncommitted paths"
    if commits < 3:
        return "FAIL", evidence
    if dirty_count > 0:
        return "WARN", evidence + " (commit the working tree before submitting)"
    return "PASS", evidence


def check_runnable(root: Path, skip_build: bool):
    moon = find_moon()
    if not moon:
        return "WARN", "moon executable not found in PATH or ~/.moon/bin"
    if skip_build:
        return "WARN", "build/test skipped by --skip-build"
    code, text, secs = run([moon, "build", "--target", "native"], root)
    if code != 0:
        tail = "\n".join(text.strip().splitlines()[-8:])
        return "FAIL", f"moon build failed ({secs:.1f}s): {tail[:400]}"
    code, text, secs = run([moon, "test"], root)
    match = re.search(r"Total tests:\s*(\d+),\s*passed:\s*(\d+),\s*failed:\s*(\d+)", text)
    if not match:
        return "WARN", "moon test ran but the summary could not be parsed"
    total, passed, failed = (int(x) for x in match.groups())
    if failed != 0:
        return "FAIL", f"{failed}/{total} tests failed"
    return "PASS", f"build ok, {passed}/{total} tests passed ({secs:.0f}s test run)"


def check_readme(root: Path):
    readme = None
    for name in ("README.md", "README.mbt.md", "readme.md"):
        candidate = root / name
        if candidate.exists():
            readme = candidate
            break
    if readme is None:
        return "FAIL", "no README.md"
    text = read_text(readme).lower()
    has_command = any(token in text for token in ("moon build", "moon run", "moon test"))
    has_section = any(token in text for token in ("quick start", "usage", "getting started", "快速开始", "使用"))
    if has_command and has_section:
        return "PASS", f"{readme.name} documents commands and a quickstart section"
    missing = "commands" if not has_command else "quickstart section"
    return "WARN", f"{readme.name} is missing the {missing}"


def check_license(root: Path):
    license_file = None
    for candidate in root.glob("LICENSE*"):
        if candidate.is_file():
            license_file = candidate
            break
    moon_mod = read_text(root / "moon.mod", 4000)
    field = re.search(r'license\s*=\s*"([^"]*)"', moon_mod)
    declared = field.group(1) if field else ""
    if license_file is None and not declared:
        return "FAIL", "no LICENSE file and no license field in moon.mod"
    text = read_text(license_file, 6000) if license_file else ""
    root_ok = bool(OSI_RE.search(text)) or bool(OSI_RE.search(declared))
    unknown = {}
    for mod in root.glob(".mooncakes/*/*/moon.mod"):
        name = mod.parent.name
        mtext = read_text(mod, 3000)
        m = re.search(r'license\s*=\s*"([^"]*)"', mtext)
        lic = m.group(1) if m else ""
        if lic and not OSI_RE.search(lic):
            unknown[name] = lic
    evidence = f"root={'LICENSE+' if license_file else ''}{declared or 'no field'}; " + (
        f"dependency licences unrecognised: {unknown}" if unknown else "dependency licences look OSI-compatible"
    )
    if not root_ok:
        return "FAIL", evidence
    if unknown:
        return "WARN", evidence
    return "PASS", evidence


def check_ai_explainable(root: Path):
    docs = root / "docs"
    adr_count = 0
    decisions = docs / "decisions.md"
    if decisions.exists():
        adr_count = len(re.findall(r"^## D\d+", read_text(decisions, 200000), re.MULTILINE))
    mentions_ai = False
    for path in list(docs.glob("*.md")) if docs.exists() else []:
        text = read_text(path).lower()
        if "ai" in text and ("llm" in text or "assistant" in text or "codex" in text or "claude" in text):
            mentions_ai = True
            break
    if adr_count >= 5 or mentions_ai:
        return "PASS", f"{adr_count} ADR entries; AI usage documented={mentions_ai}"
    return "WARN", f"only {adr_count} ADR entries and no AI-usage note — judges ask how AI was used"


def check_demo(root: Path):
    readme = ""
    for name in ("README.md", "README.mbt.md"):
        if (root / name).exists():
            readme = read_text(root / name).lower()
            break
    has_entry = (root / "cmd").exists() or (root / "examples").exists()
    has_demo_doc = any(token in readme for token in ("demo", "example", "quick start", "quickstart"))
    if has_entry and has_demo_doc:
        return "PASS", "entry point (cmd/ or examples/) plus a documented demo"
    if has_entry or has_demo_doc:
        return "WARN", "entry point or demo doc present, but not both"
    return "WARN", "no entry point (cmd/, examples/) and no demo section in README"


def check_assertions(root: Path):
    files = 0
    assertions = 0
    for pattern in ("*_test.mbt", "*_wbtest.mbt"):
        for path in root.rglob(pattern):
            if any(part in SKIP_DIRS for part in path.parts):
                continue
            files += 1
            text = read_text(path, 200000)
            assertions += (
                text.count("assert_eq")
                + text.count("assert_true")
                + text.count("assert_false")
                + text.count("inspect(")
            )
    if files >= 3 and assertions >= 10:
        return "PASS", f"{files} test files, {assertions} assertions"
    return "WARN", f"{files} test files, {assertions} assertions — thin coverage"


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="MoonBit hackathon acceptance checker")
    parser.add_argument("--project", default=".", help="project root (default: cwd)")
    parser.add_argument("--since", default="", help="round start date, e.g. 2026-11-01")
    parser.add_argument("--skip-build", action="store_true", help="skip moon build/test")
    parser.add_argument("--json", action="store_true", help="machine-readable output")
    args = parser.parse_args(argv)

    root = Path(args.project).resolve()
    if not (root / "moon.mod").exists():
        out(f"FAIL  no moon.mod under {root} (is this a MoonBit module?)")
        return 2

    checks = [
        ("MoonBit primary", check_moonbit_primary(root)),
        ("History", check_history(root, args.since)),
        ("Runnable", check_runnable(root, args.skip_build)),
        ("README", check_readme(root)),
        ("Licence", check_license(root)),
        ("AI explainable", check_ai_explainable(root)),
        ("Demo entry", check_demo(root)),
        ("Tests", check_assertions(root)),
    ]

    if args.json:
        out(json.dumps({
            "project": str(root),
            "checks": [{"name": n, "status": s, "evidence": e} for n, (s, e) in checks],
            "fails": sum(1 for _, (s, _) in checks if s == "FAIL"),
        }, ensure_ascii=False, indent=2))
    else:
        width = max(len(n) for n, _ in checks)
        out(f"MoonBit hackathon acceptance — {root}")
        out("")
        for name, (status, evidence) in checks:
            out(f"{status:5} {name:{width}}  {evidence}")
        fails = sum(1 for _, (s, _) in checks if s == "FAIL")
        warns = sum(1 for _, (s, _) in checks if s == "WARN")
        out("")
        out(f"{len(checks) - fails - warns} pass, {warns} warn, {fails} fail")

    return 0 if all(s != "FAIL" for _, (s, _) in checks) else 1


if __name__ == "__main__":
    raise SystemExit(main())
