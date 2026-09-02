#!/usr/bin/env python3
"""Insert explicit balanced splitter trees and loss regenerators."""

import argparse
import hashlib
import json
import math
from collections import defaultdict
from pathlib import Path


def load(path):
    return json.loads(Path(path).read_text())


def sinks_by_bit(module):
    sinks = defaultdict(list)
    for port in module["ports"].values():
        if port["direction"] == "output":
            for index, bit in enumerate(port["bits"]):
                if isinstance(bit, int):
                    sinks[bit].append((port["bits"], index, None))
    for cell in module["cells"].values():
        for port, bits in cell["connections"].items():
            if cell.get("port_directions", {}).get(port) == "input":
                for index, bit in enumerate(bits):
                    if isinstance(bit, int):
                        sinks[bit].append((bits, index, cell["type"]))
    return sinks


def insert(module, cell_db):
    original_cells = list(module["cells"].values())
    all_bits = [
        bit
        for port in module["ports"].values()
        for bit in port["bits"]
        if isinstance(bit, int)
    ] + [
        bit
        for cell in original_cells
        for bits in cell["connections"].values()
        for bit in bits
        if isinstance(bit, int)
    ]
    next_bit = max(all_bits, default=1) + 1
    serial = 0
    split_loss = cell_db["cells"]["P_SPLIT2"]["insertion_loss_db"]
    loss_limit = cell_db["max_unregenerated_loss_db"]
    totals = {"splitters": 0, "regenerators": 0}
    clock_bit = module["ports"]["clk"]["bits"][0]
    clock_stats = None

    def new_bit():
        nonlocal next_bit
        bit = next_bit
        next_bit += 1
        return bit

    def new_cell(kind, connections, directions):
        nonlocal serial
        name = f"$physical${kind.lower()}${serial}"
        serial += 1
        module["cells"][name] = {
            "hide_name": 1,
            "type": kind,
            "parameters": {},
            "attributes": {"physical_only": "1"},
            "port_directions": directions,
            "connections": connections,
        }

    def build_tree(source, loads, segment_loss, depth, path_regens, stats):
        if len(loads) == 1:
            sink_loss = cell_db["cells"].get(loads[0][2], {}).get(
                "insertion_loss_db", 0
            )
            if segment_loss + sink_loss > loss_limit:
                regenerated = new_bit()
                new_cell(
                    "P_REGEN2R", {"A": [source], "Y": [regenerated]},
                    {"A": "input", "Y": "output"},
                )
                source = regenerated
                segment_loss = 0
                path_regens += 1
                totals["regenerators"] += 1
                stats["inserted_regenerators"] += 1
            loads[0][0][loads[0][1]] = source
            stats["max_depth"] = max(stats["max_depth"], depth)
            stats["max_path_regenerators"] = max(
                stats["max_path_regenerators"], path_regens
            )
            stats["maximum_segment_loss_db"] = max(
                stats["maximum_segment_loss_db"], segment_loss
            )
            return
        if segment_loss + split_loss > loss_limit:
            regenerated = new_bit()
            new_cell(
                "P_REGEN2R", {"A": [source], "Y": [regenerated]},
                {"A": "input", "Y": "output"},
            )
            source = regenerated
            segment_loss = 0
            path_regens += 1
            totals["regenerators"] += 1
            stats["inserted_regenerators"] += 1
        left, right = new_bit(), new_bit()
        new_cell(
            "P_SPLIT2", {"A": [source], "Y0": [left], "Y1": [right]},
            {"A": "input", "Y0": "output", "Y1": "output"},
        )
        totals["splitters"] += 1
        stats["inserted_splitters"] += 1
        middle = (len(loads) + 1) // 2
        loss = segment_loss + split_loss
        build_tree(left, loads[:middle], loss, depth + 1, path_regens, stats)
        build_tree(right, loads[middle:], loss, depth + 1, path_regens, stats)

    for bit, loads in list(sinks_by_bit(module).items()):
        if len(loads) < 2:
            continue
        stats = {
            "loads": len(loads),
            "inserted_splitters": 0,
            "inserted_regenerators": 0,
            "max_depth": 0,
            "max_path_regenerators": 0,
            "maximum_segment_loss_db": 0,
        }
        build_tree(bit, loads, 0, 0, 0, stats)
        assert stats["inserted_splitters"] == len(loads) - 1
        assert stats["maximum_segment_loss_db"] <= loss_limit
        if bit == clock_bit:
            clock_stats = stats

    assert max((len(v) for v in sinks_by_bit(module).values()), default=0) <= 1
    assert clock_stats and clock_stats["max_depth"] == math.ceil(
        math.log2(clock_stats["loads"])
    )
    return totals, clock_stats


def self_test():
    module = {
        "ports": {
            "clk": {"direction": "input", "bits": [2]},
            "out": {"direction": "output", "bits": [3]},
        },
        "cells": {
            str(index): {
                "type": "DFF", "port_directions": {"CLK": "input"},
                "connections": {"CLK": [2]},
            }
            for index in range(5)
        },
    }
    module["cells"]["source"] = {
        "type": "BUF", "port_directions": {"Y": "output"},
        "connections": {"Y": [3]},
    }
    db = {"max_unregenerated_loss_db": 5, "cells": {
        "P_SPLIT2": {"insertion_loss_db": 3},
    }}
    totals, clock = insert(module, db)
    assert totals == {"splitters": 4, "regenerators": 3}
    assert clock["loads"] == 5 and clock["maximum_segment_loss_db"] == 3


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--netlist", default="build/photonic/top_mapped.json")
    parser.add_argument("--cells", default="photonic/cells.json")
    parser.add_argument("--output", default="build/physical/top_physical.json")
    args = parser.parse_args()
    self_test()
    netlist_path = Path(args.netlist)
    netlist = load(netlist_path)
    totals, clock = insert(netlist["modules"]["top"], load(args.cells))
    netlist["physical_support"] = {
        "logical_netlist_sha256": hashlib.sha256(netlist_path.read_bytes()).hexdigest(),
        "inserted_splitters": totals["splitters"],
        "inserted_regenerators": totals["regenerators"],
        "clock_tree": clock,
    }
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(netlist, indent=2) + "\n")
    print(
        f"PASS: inserted {totals['splitters']} splitters and "
        f"{totals['regenerators']} regenerators into {output}"
    )


if __name__ == "__main__":
    main()
