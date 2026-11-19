#!/usr/bin/env python3
"""Prove the published package is actually consumable by a third party.

Tests the distribution path rather than the source tree: create a fresh MoonBit
module elsewhere on disk, depend on the registry version (not a local path), and
build and run against the public API. A package that only works from its own
checkout is not adopted by anyone.

Usage: python tools/consumer_check.py [--version 0.3.0]
Exit code 0 = a fresh module resolved the published version, built and ran.
"""

import argparse
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile
import urllib.request

MODULE = "PingGuoMiaoMiao/docmunch"
MANIFEST_URL = f"https://mooncakes.io/api/v0/manifest/{MODULE}"

PROBE = """// Consumes the published package the way a third party would: no local path,
// no source access, only what MoonCakes serves.

///|
fn main {
  let section : @core.Section = {
    id: "demo::docs/a.md::intro#1",
    repo: "demo",
    doc_path: "docs/a.md",
    title: "Intro",
    level: 1,
    byte_start: 0,
    byte_end: 10,
    parent_id: "",
    content_hash: "00",
    terms: ["intro"],
    tokens: 1,
  }
  println("section=\\{section.id}")
  println("slug=\\{@core.slugify("Hello, World")}")
  println("index_version=\\{@core.index_version}")
  println("cjk_bigrams=\\{@text.tokenize("中文检索").length()}")
  println("lines=\\{@text.split_lines("a\\nb\\n").length()}")
}
"""

MANIFEST = """name = "consumer/probe"

version = "0.1.0"

preferred_target = "native"

import {{
  "{module}@{version}",
}}
"""

PACKAGE = """import {{
  "{module}/core",
  "{module}/core/text",
}}

pkgtype(kind: "executable")
"""


def resolve_moon():
    for candidate in (pathlib.Path.home() / ".moon" / "bin" / "moon.exe",
                      pathlib.Path.home() / ".moon" / "bin" / "moon"):
        if candidate.exists():
            return candidate
    found = shutil.which("moon")
    return pathlib.Path(found) if found else None


MOON = resolve_moon()


def latest_version():
    try:
        with urllib.request.urlopen(MANIFEST_URL, timeout=30) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        return data.get("latest_version") or (data.get("version") if isinstance(data, dict) else None)
    except Exception as exc:  # noqa: BLE001 - report verbatim
        print(f"could not read the registry manifest: {exc}")
        return None


def run(args, cwd):
    return subprocess.run([str(MOON), *args], cwd=cwd, capture_output=True,
                          text=True, encoding="utf-8", errors="replace", timeout=900)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", default=None, help="registry version to consume")
    args = parser.parse_args()

    if MOON is None:
        print("moon not found on PATH or in ~/.moon/bin")
        return 2

    version = args.version or latest_version()
    if not version:
        print("no version to test")
        return 2
    print(f"consuming {MODULE}@{version} from the registry")

    work = pathlib.Path(tempfile.mkdtemp(prefix="docmunch-consumer-"))
    project = work / "probe"
    try:
        project.mkdir()
        (project / "moon.mod").write_text(
            MANIFEST.format(module=MODULE, version=version), encoding="utf-8")
        (project / "moon.pkg").write_text(PACKAGE.format(module=MODULE), encoding="utf-8")
        (project / "main.mbt").write_text(PROBE, encoding="utf-8")

        built = run(["build", "--target", "native"], project)
        if built.returncode != 0:
            print("FAIL moon build")
            print((built.stdout + built.stderr)[-1500:])
            return 1
        print("build: ok")

        exe = project / "_build" / "native" / "debug" / "build" / "probe.exe"
        if not exe.exists():
            exe = project / "_build" / "native" / "debug" / "build" / "probe"
        if not exe.exists():
            print("FAIL binary not found after build")
            return 1
        ran = subprocess.run([str(exe)], capture_output=True, text=True,
                             encoding="utf-8", errors="replace")
        print("run output:")
        for line in ran.stdout.strip().splitlines():
            print("  " + line)
        if ran.returncode != 0:
            print("FAIL run")
            print(ran.stderr[-800:])
            return 1
    finally:
        shutil.rmtree(work, ignore_errors=True)

    print("\nconsumer check passed: a fresh module resolved the published version, "
          "built and ran against it")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
