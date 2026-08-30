#!/usr/bin/env python3
"""Bounded structural checks for the mapped photonic CPU netlist."""

import argparse
import json
from collections import Counter
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("netlist", nargs="?", default="build/photonic/top_mapped.json")
    args = parser.parse_args()
    module = json.loads(Path(args.netlist).read_text())["modules"]["top"]
    cells = module["cells"]
    counts = Counter(cell["type"] for cell in cells.values())
    allowed = {
        "P_CHI2_LUT3", "P_TBIN_DFF", "P_TBIN_DFFR", "P_PC32",
        "P_PMP32", "P_MULDIV32", "P_FPU64", "P_MEM_ASYNC",
    }
    unknown = set(counts) - allowed
    assert not unknown, f"unmapped cell types: {sorted(unknown)}"
    drivers = Counter(
        bit for port in module["ports"].values()
        if port["direction"] == "input"
        for bit in port["bits"] if isinstance(bit, int)
    )
    for cell in cells.values():
        for port, bits in cell["connections"].items():
            if cell["port_directions"].get(port) == "output":
                drivers.update(bit for bit in bits if isinstance(bit, int))
            assert all(not isinstance(bit, str) or bit in ("0", "1")
                       for bit in bits), "mapped netlist contains X/Z constants"
    multiply_driven = [bit for bit, count in drivers.items() if count != 1]
    assert not multiply_driven, f"multiply driven mapped nets: {multiply_driven[:20]}"
    driven = set(drivers)
    floating = []
    for name, cell in cells.items():
        for port, bits in cell["connections"].items():
            if cell["port_directions"].get(port) == "input":
                floating.extend(
                    f"{name}.{port}[{index}]" for index, bit in enumerate(bits)
                    if isinstance(bit, int) and bit not in driven
                )
    for name, port in module["ports"].items():
        if port["direction"] == "output":
            floating.extend(
                f"top.{name}[{index}]" for index, bit in enumerate(port["bits"])
                if isinstance(bit, int) and bit not in driven
            )
    assert not floating, f"undriven mapped nets: {floating[:20]}"
    assert counts["P_CHI2_LUT3"] and counts["P_TBIN_DFF"]
    assert {name: counts[name] for name in ("P_PC32", "P_MULDIV32", "P_FPU64")} == {
        "P_PC32": 1, "P_MULDIV32": 1, "P_FPU64": 1,
    }
    assert counts["P_PMP32"] == 8
    assert counts["P_MEM_ASYNC"] == 6
    assert counts["P_CHI2_LUT3"] <= 17_000, "photonic LUT budget regressed"
    assert counts["P_TBIN_DFF"] <= 3_500, "soft-state budget regressed"
    memory_shapes = Counter(
        tuple(int(cell.get("parameters", {}).get(name, "1"), 2)
              for name in ("DATA_WIDTH", "ADDR_WIDTH", "READ_PORTS",
                           "BYTE_LANES"))
        for cell in cells.values() if cell["type"] == "P_MEM_ASYNC"
    )
    assert memory_shapes == Counter({
        (32, 5, 2, 1): 1, (64, 5, 3, 1): 1,
        (32, 6, 2, 4): 2, (24, 4, 2, 1): 1, (24, 4, 1, 1): 1,
    }), f"unexpected memory macros: {memory_shapes}"
    rst_bits = module["ports"]["rst_n"]["bits"]
    assert all(cell["connections"].get("rst_n") == rst_bits
               for cell in cells.values() if cell["type"] == "P_MEM_ASYNC"), (
        "every memory macro must use the top-level deterministic reset"
    )
    print("PASS: mapped photonic netlist contract", dict(sorted(counts.items())))


if __name__ == "__main__":
    main()
