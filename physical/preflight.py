#!/usr/bin/env python3
"""Build a photonic netlist manifest and enforce the PIC release gate."""

import argparse
import hashlib
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
    parser.add_argument("--physical-netlist",
                        default="build/physical/top_physical.json")
    parser.add_argument("--cells", default="photonic/cells.json")
    parser.add_argument("--assembly", default="physical/assembly.json")
    parser.add_argument("--signoff", default="physical/signoff.json")
    parser.add_argument("--output", default="build/physical/preflight.json")
    parser.add_argument("--require-release", action="store_true")
    args = parser.parse_args()

    cell_db = load(args.cells)
    assembly = load(args.assembly)
    logical_path = Path(args.netlist)
    counts, signal_bits, max_fanout, splitters = analyze_netlist(load(logical_path))
    reasons = []

    used_photonic = sorted(name for name in counts if name.startswith("P_"))
    required_physical = sorted(cell_db["cells"])
    for name in required_physical:
        metadata = cell_db["cells"][name]
        if not metadata.get("gds_cell"):
            reasons.append(f"missing vendor GDS cell: {name}")
        elif not Path(metadata["gds_cell"]).exists():
            reasons.append(f"vendor GDS cell does not exist: {metadata['gds_cell']}")

    inserted_splitters = inserted_regenerators = 0
    physical_path = Path(args.physical_netlist)
    if not physical_path.exists():
        reasons.append(f"missing inserted physical netlist: {args.physical_netlist}")
    else:
        physical = load(physical_path)
        support = physical.get("physical_support", {})
        physical_counts, _, physical_fanout, _ = analyze_netlist(physical)
        digest = hashlib.sha256(logical_path.read_bytes()).hexdigest()
        if support.get("logical_netlist_sha256") != digest:
            reasons.append("inserted physical netlist is stale")
        inserted_splitters = physical_counts["P_SPLIT2"]
        inserted_regenerators = physical_counts["P_REGEN2R"]
        if inserted_splitters != splitters:
            reasons.append(
                f"splitter insertion incomplete: {inserted_splitters}/{splitters}"
            )
        if inserted_regenerators <= 0:
            reasons.append("no physical regenerators were inserted")
        if physical_fanout > 1:
            reasons.append(f"physical netlist retains fanout {physical_fanout}")
        if support.get("inserted_splitters") != inserted_splitters or \
                support.get("inserted_regenerators") != inserted_regenerators:
            reasons.append("physical support manifest does not match its netlist")
        maximum_loss = (support.get("clock_tree") or {}).get(
            "maximum_segment_loss_db", 0
        )
        if maximum_loss > cell_db["max_unregenerated_loss_db"]:
            reasons.append("inserted clock tree exceeds the loss limit")
        for name, count in counts.items():
            if physical_counts[name] != count:
                reasons.append(f"physical netlist changed logical cell count: {name}")

    lower_names = " ".join(counts).lower()
    for forbidden in FORBIDDEN:
        if forbidden in lower_names:
            reasons.append(f"forbidden O/E/O cell present: {forbidden}")

    if cell_db.get("status") != "vendor-characterized":
        reasons.append("cell library is not vendor-characterized")
    minimum_clock_ghz = 1000 / cell_db["target_cycle_ps"]
    for name in required_physical:
        metadata = cell_db["cells"][name]
        for field, label in (
            ("maximum_clock_rate_ghz", "clock"),
            ("maximum_symbol_rate_ghz", "symbol"),
        ):
            if field not in metadata:
                continue
            maximum_rate = metadata[field]
            if not isinstance(maximum_rate, (int, float)) or \
                    maximum_rate < minimum_clock_ghz:
                reasons.append(
                    f"{name} {label} rate is below {minimum_clock_ghz:g} GHz"
                )
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
        if signoff.get("inserted_regenerators") is not None and \
                signoff["inserted_regenerators"] != inserted_regenerators:
            reasons.append("signoff regenerator count does not match physical netlist")

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
        "inserted_splitters": inserted_splitters,
        "inserted_regenerators": inserted_regenerators,
        "used_photonic_cells": used_photonic,
        "required_physical_cells": required_physical,
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
