#!/usr/bin/env python3
"""Netlist-based CDC/RDC checks for the JTAG transport clock domains."""

import json
from pathlib import Path


def load(path, module):
    return json.loads(Path(path).read_text())["modules"][module]


def sequential(cell):
    return "dff" in cell["type"].lower()


def combinational_cones(module):
    drivers = {}
    for cell in module["cells"].values():
        if sequential(cell):
            continue
        inputs = [
            bit for port, bits in cell["connections"].items()
            if cell.get("port_directions", {}).get(port) == "input"
            for bit in bits if isinstance(bit, int)
        ]
        for port, bits in cell["connections"].items():
            if cell.get("port_directions", {}).get(port) == "output":
                for bit in bits:
                    if isinstance(bit, int):
                        drivers[bit] = inputs

    def cone(bit):
        pending, seen = [bit], set()
        while pending:
            current = pending.pop()
            if current in seen:
                continue
            seen.add(current)
            pending.extend(drivers.get(current, ()))
        return seen

    return cone


def async_net(module, name):
    net = module["netnames"][name]
    assert net.get("attributes", {}).get("ASYNC_REG") == "TRUE", (
        f"{name} lost ASYNC_REG placement metadata"
    )
    assert len(net["bits"]) == 2, f"{name} is not a two-flop synchronizer"
    return net["bits"]


def synchronizer(module, name, source, clock, cone):
    q = async_net(module, name)
    matches = [
        cell for cell in module["cells"].values()
        if sequential(cell) and cell["connections"].get("Q") == q
    ]
    assert len(matches) == 1, f"{name} does not map to one two-bit register"
    cell = matches[0]
    assert cell["connections"]["CLK"] == [clock], f"{name} uses the wrong clock"
    d = cell["connections"]["D"]
    assert source in cone(d[0]), f"{name}[0] does not sample its async source"
    assert q[0] in cone(d[1]), f"{name}[1] does not sample {name}[0]"
    return cell


def main():
    debug = load("build/cdc/debug.json", "riscv_debug_transport")
    debug_cone = combinational_cones(debug)
    core_clock = debug["ports"]["core_clk"]["bits"][0]
    tck = debug["ports"]["tck"]["bits"][0]
    req = synchronizer(
        debug, "req_toggle_sync_core",
        debug["netnames"]["req_toggle_tck"]["bits"][0], core_clock,
        debug_cone,
    )
    rsp = synchronizer(
        debug, "rsp_toggle_sync_tck",
        debug["netnames"]["rsp_toggle_core"]["bits"][0], tck,
        debug_cone,
    )
    trst = debug["ports"]["trst_n"]["bits"][0]
    async_reset_cells = [
        cell for cell in debug["cells"].values() if cell["type"] == "$adff"
    ]
    assert async_reset_cells, "TAP reset is not represented structurally"
    assert all(cell["connections"]["CLK"] == [tck] and
               cell["connections"]["ARST"] == [trst]
               for cell in async_reset_cells), "async reset escapes the TAP domain"
    assert req["type"] == "$dff" and rsp["type"] == "$adff"
    print(
        "PASS: JTAG CDC/RDC analysis: 2 two-flop synchronizers, "
        f"{len(async_reset_cells)} TAP-only async-reset banks"
    )


if __name__ == "__main__":
    main()
