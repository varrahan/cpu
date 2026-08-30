#!/usr/bin/env python3
"""Fail when any mapped-netlist signal remains X/Z after reset."""

import argparse
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("vcd", nargs="?", default="build/photonic/known_state.vcd")
    args = parser.parse_args()
    scopes = []
    aliases = {}
    values = {}
    reset_codes = set()
    reset_released = False
    time = 0
    unknown = {}
    ignored = {"address", "lane", "index", "read_port"}

    def physical_names(code):
        return [
            name for depth, name, reference in aliases.get(code, [])
            if depth >= 3 and reference.split("[")[0] not in ignored
        ]

    def record_unknown(code, value):
        if reset_released and any(bit in value for bit in "xz"):
            for name in physical_names(code):
                unknown.setdefault(name, time)

    for raw_line in Path(args.vcd).read_text().splitlines():
        line = raw_line.strip()
        if line.startswith("$scope "):
            scopes.append(line.split()[2])
        elif line == "$upscope $end":
            scopes.pop()
        elif line.startswith("$var "):
            fields = line.split()
            aliases.setdefault(fields[3], []).append(
                (len(scopes), ".".join([*scopes, fields[4]]), fields[4])
            )
            if fields[4] == "rst_n":
                reset_codes.add(fields[3])
        elif line.startswith("#"):
            time = int(line[1:])
        elif line[:1] in "01xXzZ":
            code, value = line[1:], line[0].lower()
            values[code] = value
            if code in reset_codes:
                reset_released = value == "1"
                if reset_released:
                    for known_code, known_value in values.items():
                        record_unknown(known_code, known_value)
            record_unknown(code, value)
        elif line[:1] in "bB":
            value, code = line[1:].split(None, 1)
            values[code] = value.lower()
            record_unknown(code, value.lower())
    assert reset_codes, "VCD does not contain rst_n"
    if unknown:
        failures = [f"{name}@{unknown[name]}" for name in sorted(unknown)]
        raise SystemExit(
            f"FAIL: {len(unknown)} mapped signals remain X/Z: " +
            ", ".join(failures)
        )
    checked = sum(any(depth >= 3 and reference.split("[")[0] not in ignored
                      for depth, _, reference in aliases.get(code, []))
                  for code in values)
    print(f"PASS: {checked} mapped cell signals stayed binary after reset")


if __name__ == "__main__":
    main()
