#!/usr/bin/env python3
"""Build a photonic netlist manifest and enforce the PIC release gate."""

import argparse
import json
from collections import Counter, defaultdict
from pathlib import Path


FORBIDDEN = ("photodetector", "adc", "dac", "electrical_modulator", "electrical_gate")
STATE_CELL = "P_TBIN_DFF"
REQUIRED_SIGNOFF = (
    "clock_frequency_ghz",
    "worst_case_path_ps",
    "drc_errors",
    "connectivity_errors",
    "minimum_receiver_margin_db",
    "inserted_regenerators",
)


def load(path):
    return json.loads(Path(path).read_text())


def analyze_netlist(netlist):
    module = netlist["modules"]["top"]
    cells = module["cells"]
    counts = Counter(cell["type"] for cell in cells.values())
    sinks = defaultdict(int)
    bits = set()

    for port in module["ports"].values():
        for bit in port["bits"]:
            if isinstance(bit, int):
                bits.add(bit)
                if port["direction"] == "output":
                    sinks[bit] += 1

    for cell in cells.values():
        for port, connections in cell["connections"].items():
            direction = cell.get("port_directions", {}).get(port)
            for bit in connections:
                if isinstance(bit, int):
                    bits.add(bit)
                    if direction == "input":
                        sinks[bit] += 1

    # A binary splitter tree serving N loads contains N-1 splitter cells.
    splitters = sum(max(0, fanout - 1) for fanout in sinks.values())
    return counts, len(bits), max(sinks.values(), default=0), splitters


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--netlist", default="build/photonic/top_mapped.json")
    parser.add_argument("--cells", default="photonic/cells.json")
    parser.add_argument("--assembly", default="physical/assembly.json")
    parser.add_argument("--signoff", default="physical/signoff.json")
    parser.add_argument("--output", default="build/physical/preflight.json")
    parser.add_argument("--require-release", action="store_true")
    args = parser.parse_args()

    cell_db = load(args.cells)
    assembly = load(args.assembly)
    counts, signal_bits, max_fanout, splitters = analyze_netlist(load(args.netlist))
    reasons = []

    used_photonic = sorted(name for name in counts if name.startswith("P_"))
    for name in used_photonic:
        metadata = cell_db["cells"].get(name)
        if not metadata:
            reasons.append(f"missing cell metadata: {name}")
        elif not metadata.get("gds_cell"):
            reasons.append(f"missing vendor GDS cell: {name}")
        elif not Path(metadata["gds_cell"]).exists():
            reasons.append(f"vendor GDS cell does not exist: {metadata['gds_cell']}")

    lower_names = " ".join(counts).lower()
    for forbidden in FORBIDDEN:
        if forbidden in lower_names:
            reasons.append(f"forbidden O/E/O cell present: {forbidden}")

    if cell_db.get("status") != "vendor-characterized":
        reasons.append("cell library is not vendor-characterized")
    minimum_clock_ghz = 1000 / cell_db["target_cycle_ps"]
    for name in (STATE_CELL, "P_SPLIT2", "P_REGEN2R"):
        maximum_rate = cell_db["cells"][name].get("maximum_clock_rate_ghz")
        if not isinstance(maximum_rate, (int, float)) or maximum_rate < minimum_clock_ghz:
            reasons.append(f"{name} is not characterized for {minimum_clock_ghz:g} GHz")
    for name in used_photonic:
        if name == STATE_CELL:
            continue
        maximum_rate = cell_db["cells"][name].get("maximum_symbol_rate_ghz")
        if not isinstance(maximum_rate, (int, float)) or maximum_rate < minimum_clock_ghz:
            reasons.append(f"{name} is not rate-qualified for {minimum_clock_ghz:g} GHz")
    if assembly.get("status") != "release":
        reasons.append("assembly floorplan is still preliminary")
    if assembly["interfaces"].get("maximum_lateral_error_um") is None:
        reasons.append("coupling tolerance is not characterized")
    for chiplet in assembly["chiplets"]:
        if chiplet.get("x") is None or chiplet.get("y") is None:
            reasons.append(f"chiplet is not placed: {chiplet['name']}")

    signoff_path = Path(args.signoff)
    if not signoff_path.exists():
        reasons.append(f"missing extracted signoff report: {args.signoff}")
    else:
        signoff = load(signoff_path)
        for field in REQUIRED_SIGNOFF:
            if signoff.get(field) is None:
                reasons.append(f"missing signoff field: {field}")
        timing = signoff.get("worst_case_path_ps")
        if isinstance(timing, (int, float)) and timing > cell_db["target_cycle_ps"]:
            reasons.append(
                f"extracted worst-case path exceeds {cell_db['target_cycle_ps']:g} ps"
            )
        frequency = signoff.get("clock_frequency_ghz")
        if isinstance(frequency, (int, float)) and frequency < minimum_clock_ghz:
            reasons.append(f"extracted clock is below {minimum_clock_ghz:g} GHz")
        if signoff.get("drc_errors") not in (None, 0):
            reasons.append("DRC is not clean")
        if signoff.get("connectivity_errors") not in (None, 0):
            reasons.append("connectivity is not clean")
        margin = signoff.get("minimum_receiver_margin_db")
        if isinstance(margin, (int, float)) and margin <= 0:
            reasons.append("optical receiver power margin is not positive")

    for item in [assembly["interposer"], *assembly["chiplets"]]:
        if not Path(item["gds"]).exists():
            reasons.append(f"missing layout: {item['gds']}")

    output = {
        "release_ready": not reasons,
        "target_cycle_ps": cell_db["target_cycle_ps"],
        "minimum_clock_frequency_ghz": minimum_clock_ghz,
        "logical_cell_counts": dict(sorted(counts.items())),
        "logical_signal_bits": signal_bits,
        "dual_rail_waveguides_before_wdm": signal_bits * 2,
        "maximum_logical_fanout": max_fanout,
        "required_binary_splitters": splitters,
        "inserted_regenerators": None,
        "used_photonic_cells": used_photonic,
        "blocked_by": reasons,
    }
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(output, indent=2) + "\n")
    print(f"{'READY' if not reasons else 'BLOCKED'}: {output_path} ({len(reasons)} release gates)")
    if args.require_release and reasons:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
