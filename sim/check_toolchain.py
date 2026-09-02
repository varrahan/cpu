#!/usr/bin/env python3
"""Fail when the clean-checkout qualification toolchain drifts."""

import json
import subprocess
from pathlib import Path


def output(command):
    return subprocess.run(command, check=True, text=True,
                          stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT).stdout


def main():
    root = Path(__file__).resolve().parents[1]
    lock = json.loads((root / "tools.lock.json").read_text())
    for tool in lock["tools"]:
        actual = output(tool["command"])
        assert tool["contains"] in actual, (
            f"{' '.join(tool['command'])}: expected {tool['contains']!r}"
        )
    source_paths = {
        "act4": root / "build/act4/source",
        "softfloat": root / "build/softfloat/source",
    }
    for name, revision in lock["sources"].items():
        actual = output(["git", "-C", str(source_paths[name]), "rev-parse", "HEAD"]).strip()
        assert actual == revision, f"{name}: {actual} != {revision}"
    makefile = (root / "Makefile").read_text()
    assert lock["containers"]["act4"] in makefile
    print(f"PASS: {len(lock['tools'])} tools and {len(lock['sources'])} sources match tools.lock.json")


if __name__ == "__main__":
    main()
