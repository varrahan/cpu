#!/usr/bin/env python3
"""Estimate mapped photonic data paths and balanced clock-tree budgets."""

import argparse
import json
import math
from collections import defaultdict, deque
from dataclasses import dataclass
from pathlib import Path

STATE_CELL = "P_TBIN_DFF"
STATE_CELLS = (STATE_CELL, "P_TBIN_DFFR")
MACRO_CELLS = ("P_PC32", "P_MULDIV32", "P_FPU64")
MEMORY_CELLS = ("P_MEM_ASYNC",)
CLOCK_CELLS = STATE_CELLS + MACRO_CELLS + MEMORY_CELLS + (
    "P_SPLIT2", "P_REGEN2R",
)


@dataclass(frozen=True)
class Trace:
    delay_ps: float
    logic_levels: int
    origin: str
    previous: object = None
    cell_name: str = None
    segment_loss_db: float = 0
    total_loss_db: float = 0
    regenerator_count: int = 0


def load(path):
    return json.loads(Path(path).read_text())


def cell_delay(cell_db, cell_type, corner):
    delay = cell_db["cells"].get(cell_type, {}).get("delay_ps")
    if not isinstance(delay, dict) or not isinstance(delay.get(corner), (int, float)):
        raise ValueError(f"missing {corner} delay for combinational cell {cell_type}")
    return delay[corner]


def advance(trace, cell_db, corner, delay_ps, loss_db,
            logic_levels=0, cell_name=None, regenerates_signal=False):
    loss_limit = cell_db["max_unregenerated_loss_db"]
    accumulated_loss = trace.segment_loss_db + loss_db
    regenerators = max(0, math.ceil(accumulated_loss / loss_limit) - 1)
    regeneration_delay = (
        regenerators * cell_db["cells"]["P_REGEN2R"]["delay_ps"][corner]
    )
    return Trace(
        delay_ps=trace.delay_ps + delay_ps + regeneration_delay,
        logic_levels=trace.logic_levels + logic_levels,
        origin=trace.origin,
        previous=trace,
        cell_name=cell_name,
        segment_loss_db=0 if regenerates_signal else
                        accumulated_loss - regenerators * loss_limit,
        total_loss_db=trace.total_loss_db + loss_db,
        regenerator_count=trace.regenerator_count + regenerators,
    )


def path_analysis(module, cell_db, corner, source_kind,
                  endpoint_ports=("D",)):
    cells = module["cells"]
    combinational = {name: cell for name, cell in cells.items()
                     if cell["type"] not in STATE_CELLS and
                     cell["type"] not in MACRO_CELLS}
    output_driver = {}
    fanouts = defaultdict(int)
    for name, cell in combinational.items():
        for port, bits in cell["connections"].items():
            if cell["port_directions"].get(port) == "output":
                for bit in bits:
                    if isinstance(bit, int):
                        output_driver[bit] = name
    for port in module["ports"].values():
        if port["direction"] == "output":
            for bit in port["bits"]:
                if isinstance(bit, int):
                    fanouts[bit] += 1
    for cell in cells.values():
        for port, bits in cell["connections"].items():
            if cell["port_directions"].get(port) == "input":
                for bit in bits:
                    if isinstance(bit, int):
                        fanouts[bit] += 1

    dependencies = {name: set() for name in combinational}
    successors = defaultdict(set)
    for name, cell in combinational.items():
        combinational_ports = cell_db["cells"][cell["type"]].get(
            "combinational_input_ports"
        )
        for port, bits in cell["connections"].items():
            if cell["port_directions"].get(port) != "input":
                continue
            if combinational_ports and port not in combinational_ports:
                continue
            for bit in bits:
                driver = output_driver.get(bit)
                if driver and driver != name:
                    dependencies[name].add(driver)
                    successors[driver].add(name)

    queue = deque(name for name, deps in dependencies.items() if not deps)
    order = []
    while queue:
        name = queue.popleft()
        order.append(name)
        for successor in successors[name]:
            dependencies[successor].remove(name)
            if not dependencies[successor]:
                queue.append(successor)
    if len(order) != len(combinational):
        remaining = [(name, sorted(deps)[:3]) for name, deps in dependencies.items()
                     if deps][:5]
        raise ValueError(
            f"combinational loop includes {len(combinational) - len(order)} cells: "
            f"{remaining}"
        )

    # Trace tuple: delay, LUT levels, origin, previous trace, cell name.
    arrivals = {}
    source_origins = defaultdict(set)
    if source_kind == "latch":
        cq = cell_db["cells"][STATE_CELL]["clock_to_q_ps"][corner]
        for name, cell in cells.items():
            if cell["type"] in STATE_CELLS:
                for bit in cell["connections"]["Q"]:
                    if isinstance(bit, int):
                        arrivals[bit] = Trace(cq, 0, name)
                        source_origins[bit].add(name)
        for name, cell in cells.items():
            if cell["type"] in MACRO_CELLS:
                cq = cell_db["cells"][cell["type"]]["clock_to_output_ps"]
                for port, bits in cell["connections"].items():
                    if cell["port_directions"].get(port) == "output":
                        for bit in bits:
                            if isinstance(bit, int):
                                arrivals[bit] = Trace(cq, 0, name)
                                source_origins[bit].add(name)
    elif source_kind == "input":
        for port_name, port in module["ports"].items():
            if port["direction"] == "input" and port_name != "clk":
                for bit in port["bits"]:
                    if isinstance(bit, int):
                        arrivals[bit] = Trace(0, 0, port_name)
                        source_origins[bit].add(port_name)
    else:
        raise ValueError(f"unknown source kind: {source_kind}")

    for name in order:
        cell = combinational[name]
        candidates = []
        cell_origins = set()
        combinational_ports = cell_db["cells"][cell["type"]].get(
            "combinational_input_ports"
        )
        for port, bits in cell["connections"].items():
            if cell["port_directions"].get(port) == "input":
                if combinational_ports and port not in combinational_ports:
                    continue
                for bit in bits:
                    if bit not in arrivals:
                        continue
                    cell_origins.update(source_origins[bit])
                    splitter_levels = (
                        math.ceil(math.log2(fanouts[bit]))
                        if fanouts[bit] > 1 else 0
                    )
                    splitter = cell_db["cells"]["P_SPLIT2"]
                    candidates.append(advance(
                        arrivals[bit], cell_db, corner,
                        splitter_levels * splitter["delay_ps"][corner],
                        splitter_levels * splitter["insertion_loss_db"],
                    ))
        if not candidates:
            continue
        previous = max(candidates, key=lambda trace: trace.delay_ps)
        metadata = cell_db["cells"][cell["type"]]
        trace = advance(
            previous, cell_db, corner,
            cell_delay(cell_db, cell["type"], corner),
            metadata.get("insertion_loss_db", 0),
            logic_levels=1,
            cell_name=name,
            regenerates_signal=metadata.get("regenerates_signal", False),
        )
        for port, bits in cell["connections"].items():
            if cell["port_directions"].get(port) == "output":
                for bit in bits:
                    if isinstance(bit, int):
                        arrivals[bit] = trace
                        source_origins[bit] = cell_origins

    endpoints = []
    for name, cell in cells.items():
        if cell["type"] in STATE_CELLS:
            reset_origins = set()
            for reset_port in ("RESET", "ARST"):
                for bit in cell["connections"].get(reset_port, []):
                    reset_origins.update(source_origins[bit])
            for port in endpoint_ports:
                for bit in cell["connections"].get(port, []):
                    if bit not in arrivals:
                        continue
                    if port == "D" and arrivals[bit].origin in reset_origins:
                        continue
                    splitter_levels = (
                        math.ceil(math.log2(fanouts[bit]))
                        if fanouts[bit] > 1 else 0
                    )
                    splitter = cell_db["cells"]["P_SPLIT2"]
                    endpoints.append((advance(
                        arrivals[bit], cell_db, corner,
                        splitter_levels * splitter["delay_ps"][corner],
                        splitter_levels * splitter["insertion_loss_db"],
                    ), name if port == "D" else f"{name}.{port}"))
        elif cell["type"] in MACRO_CELLS and "D" in endpoint_ports:
            for port, bits in cell["connections"].items():
                if (cell["port_directions"].get(port) != "input" or
                    port.lower() in {"clk", "rst_n", "reset", "flush"}):
                    continue
                for bit in bits:
                    if bit in arrivals:
                        endpoints.append((arrivals[bit], f"{name}.{port}"))
        elif cell["type"] in MEMORY_CELLS and "D" in endpoint_ports:
            state_ports = cell_db["cells"][cell["type"]]["state_input_ports"]
            for port in state_ports:
                for bit in cell["connections"].get(port, []):
                    if bit in arrivals:
                        endpoints.append((arrivals[bit], f"{name}.{port}"))
    if not endpoints:
        raise ValueError(
            f"no {source_kind}-to-{','.join(endpoint_ports)} path found")

    trace, endpoint = max(endpoints, key=lambda item: item[0].delay_ps)
    worst_endpoints = [{
        "delay_ps": item[0].delay_ps,
        "logic_levels": item[0].logic_levels,
        "origin": item[0].origin,
        "endpoint": item[1],
    } for item in sorted(endpoints, key=lambda item: item[0].delay_ps,
                         reverse=True)[:10]]
    path = []
    cursor = trace
    while cursor:
        if cursor.cell_name:
            path.append(cursor.cell_name)
        cursor = cursor.previous
    path.reverse()
    return {
        "delay_ps": trace.delay_ps,
        "logic_levels": trace.logic_levels,
        "origin": trace.origin,
        "endpoint": endpoint,
        "total_insertion_loss_db": trace.total_loss_db,
        "required_regenerators": trace.regenerator_count,
        "final_unregenerated_loss_db": trace.segment_loss_db,
        "path_tail": path[-12:],
        "worst_endpoints": worst_endpoints,
    }


def clock_tree(module, cell_db, corner):
    clk_bits = set(module["ports"]["clk"]["bits"])
    fanout = sum(1 for cell in module["cells"].values()
                 if cell["type"] in STATE_CELLS + MACRO_CELLS + MEMORY_CELLS and
                 clk_bits.intersection(cell["connections"].get(
                     "CLK", cell["connections"].get("clk", []))))
    levels = math.ceil(math.log2(fanout)) if fanout > 1 else 0
    splitter = cell_db["cells"]["P_SPLIT2"]
    path_loss = levels * splitter["insertion_loss_db"]
    regeneration_count = max(
        0,
        math.ceil(path_loss / cell_db["max_unregenerated_loss_db"]) - 1,
    )
    passive_delay = levels * splitter["delay_ps"][corner]
    regeneration_delay = (
        regeneration_count *
        cell_db["cells"]["P_REGEN2R"]["delay_ps"][corner]
    )
    return {
        "latch_fanout": fanout,
        "balanced_binary_levels": levels,
        "splitter_cells": max(0, fanout - 1),
        "path_insertion_loss_db": path_loss,
        "ideal_split_loss_db": 10 * math.log10(fanout) if fanout else 0,
        "passive_tree_delay_ps": passive_delay,
        "required_path_regenerators": regeneration_count,
        "regenerated_tree_delay_ps": passive_delay + regeneration_delay,
        "rate_characterized": all(
            isinstance(cell_db["cells"][name].get("maximum_clock_rate_ghz"),
                       (int, float))
            for name in CLOCK_CELLS
        ),
    }


def self_test():
    module = {
        "ports": {"clk": {"direction": "input", "bits": [2]}},
        "cells": {
            "launch": {"type": STATE_CELL, "port_directions": {"D": "input", "CLK": "input", "Q": "output"}, "connections": {"D": ["0"], "CLK": [2], "Q": [10]}},
            "logic0": {"type": "P_CHI2_LUT3", "port_directions": {"a": "input", "b": "input", "c": "input", "y": "output"}, "connections": {"a": [10], "b": ["0"], "c": ["0"], "y": [11]}},
            "logic1": {"type": "P_CHI2_LUT3", "port_directions": {"a": "input", "b": "input", "c": "input", "y": "output"}, "connections": {"a": [11], "b": ["0"], "c": ["0"], "y": [12]}},
            "capture": {"type": STATE_CELL, "port_directions": {"D": "input", "CLK": "input", "Q": "output"}, "connections": {"D": [12], "CLK": [2], "Q": [13]}},
        },
    }
    db = {"max_unregenerated_loss_db": 8, "cells": {
        STATE_CELL: {"clock_to_q_ps": {"maximum": 0.4}},
        "P_CHI2_LUT3": {"delay_ps": {"maximum": 0.12},
                         "insertion_loss_db": 2},
        "P_SPLIT2": {"delay_ps": {"maximum": 2}, "insertion_loss_db": 3.3,
                      "maximum_clock_rate_ghz": 200},
        "P_REGEN2R": {"delay_ps": {"maximum": 0.12}},
    }}
    result = path_analysis(module, db, "maximum", "latch")
    assert math.isclose(result["delay_ps"], 0.64) and result["logic_levels"] == 2
    assert result["required_regenerators"] == 0
    assert clock_tree(module, db, "maximum")["balanced_binary_levels"] == 1

    memory_module = {
        "ports": {"clk": {"direction": "input", "bits": [2]}},
        "cells": {
            "launch": module["cells"]["launch"],
            "memory": {
                "type": "P_MEM_ASYNC",
                "port_directions": {"clk": "input", "raddr": "input",
                                    "wdata": "input", "rdata": "output"},
                "connections": {"clk": [2], "raddr": [10],
                                "wdata": ["0"], "rdata": [11]},
            },
            "capture": {
                "type": STATE_CELL,
                "port_directions": {"D": "input", "CLK": "input",
                                    "Q": "output"},
                "connections": {"D": [11], "CLK": [2], "Q": [12]},
            },
        },
    }
    db["cells"]["P_MEM_ASYNC"] = {
        "delay_ps": {"maximum": 0.6}, "insertion_loss_db": 0,
        "combinational_input_ports": ["raddr"],
        "state_input_ports": ["wdata"],
    }
    result = path_analysis(memory_module, db, "maximum", "latch")
    assert math.isclose(result["delay_ps"], 1.0)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--netlist", default="build/photonic/top_mapped.json")
    parser.add_argument("--cells", default="photonic/cells.json")
    parser.add_argument("--output", default="build/physical/timing.json")
    parser.add_argument("--frequencies-ghz", nargs="+", type=float, default=[100])
    parser.add_argument("--minimum-frequency-ghz", type=float, default=100)
    parser.add_argument("--uncertainty-fraction", type=float, default=0.10)
    parser.add_argument("--skew-fraction", type=float, default=0.05)
    parser.add_argument("--require-model-pass", action="store_true")
    parser.add_argument("--require-pass", action="store_true")
    args = parser.parse_args()
    if any(frequency <= 0 for frequency in args.frequencies_ghz):
        parser.error("frequencies must be positive")
    if args.minimum_frequency_ghz <= 0:
        parser.error("minimum frequency must be positive")
    if max(args.frequencies_ghz) < args.minimum_frequency_ghz:
        parser.error("at least one evaluated frequency must meet the minimum target")
    if not 0 <= args.uncertainty_fraction < 1 or not 0 <= args.skew_fraction < 1:
        parser.error("uncertainty and skew fractions must be in [0, 1)")
    if args.uncertainty_fraction + args.skew_fraction >= 1:
        parser.error("combined uncertainty and skew must be below one period")

    self_test()
    cell_db = load(args.cells)
    module = load(args.netlist)["modules"]["top"]
    maximum = path_analysis(module, cell_db, "maximum", "latch")
    typical = path_analysis(module, cell_db, "typical", "latch")
    input_path = path_analysis(module, cell_db, "maximum", "input")
    reset_path = path_analysis(module, cell_db, "maximum", "latch",
                               endpoint_ports=("RESET",))
    tree = clock_tree(module, cell_db, "maximum")
    setup = max(
        *(cell_db["cells"][name]["setup_ps"] for name in STATE_CELLS),
        *(cell_db["cells"][name]["interface_setup_ps"]
          for name in MACRO_CELLS),
        *(cell_db["cells"][name]["interface_setup_ps"]
          for name in MEMORY_CELLS),
    )
    cq = cell_db["cells"][STATE_CELL]["clock_to_q_ps"]["maximum"]
    reset_recovery = cell_db["cells"]["P_TBIN_DFFR"]["reset_recovery_ps"]
    lut = cell_db["cells"]["P_CHI2_LUT3"]["delay_ps"]["maximum"]
    pulse_width = cell_db["pulse_width_ps"]
    combinational_types = {
        cell["type"] for cell in module["cells"].values()
        if cell["type"] not in STATE_CELLS and cell["type"] not in MACRO_CELLS
    }
    macros = {
        name: {
            "instances": sum(cell["type"] == name
                             for cell in module["cells"].values()),
            "maximum_clock_rate_ghz":
                cell_db["cells"][name]["maximum_clock_rate_ghz"],
            "interface_setup_ps": cell_db["cells"][name]["interface_setup_ps"],
            "clock_to_output_ps": cell_db["cells"][name]["clock_to_output_ps"],
            "latency_cycles": cell_db["cells"][name]["latency_cycles"],
        } for name in MACRO_CELLS
    }
    margin_fraction = args.uncertainty_fraction + args.skew_fraction

    targets = []
    for frequency in args.frequencies_ghz:
        period = 1000 / frequency
        uncertainty = period * args.uncertainty_fraction
        skew = period * args.skew_fraction
        required = maximum["delay_ps"] + setup + uncertainty + skew
        reset_required = (reset_path["delay_ps"] + reset_recovery +
                          uncertainty + skew)
        targets.append({
            "frequency_ghz": frequency,
            "period_ps": period,
            "uncertainty_ps": uncertainty,
            "allowed_clock_skew_ps": skew,
            "required_latch_to_latch_ps": required,
            "slack_ps": period - required,
            "logic_meets_model_timing": required <= period,
            "predicate_reset_required_ps": reset_required,
            "predicate_reset_meets_model_timing": reset_required <= period,
            "bare_latch_required_ps": cq + setup + uncertainty + skew,
            "bare_latch_meets_model_timing":
                cq + setup + uncertainty + skew <= period,
            "one_lut_required_ps": cq + lut + setup + uncertainty + skew,
            "one_lut_meets_model_timing":
                cq + lut + setup + uncertainty + skew <= period,
            "clock_tree_rate_characterized": tree["rate_characterized"],
            "clock_tree_meets_target_rate": all(
                isinstance(cell_db["cells"][name].get("maximum_clock_rate_ghz"),
                           (int, float)) and
                cell_db["cells"][name]["maximum_clock_rate_ghz"] >= frequency
                for name in CLOCK_CELLS
            ),
            "combinational_cells_meet_target_rate": all(
                isinstance(cell_db["cells"][name].get("maximum_symbol_rate_ghz"),
                           (int, float)) and
                cell_db["cells"][name]["maximum_symbol_rate_ghz"] >= frequency
                for name in combinational_types
            ),
            "macros_meet_target_rate": all(
                macro["maximum_clock_rate_ghz"] >= frequency and
                macro["interface_setup_ps"] + macro["clock_to_output_ps"] <=
                    period
                for macro in macros.values()
            ),
            "pulse_width_ps": pulse_width,
            "pulse_fits_period": pulse_width <= period,
        })

    for target in targets:
        target["target_pass"] = (
            target["logic_meets_model_timing"] and
            target["predicate_reset_meets_model_timing"] and
            target["clock_tree_meets_target_rate"] and
            target["combinational_cells_meet_target_rate"] and
            target["macros_meet_target_rate"] and
            target["pulse_fits_period"]
        )

    output = {
        "model_status": cell_db["status"],
        "timing_is_signoff": cell_db["status"] == "vendor-characterized",
        "minimum_clock_frequency_ghz": args.minimum_frequency_ghz,
        "maximum_latch_to_latch": maximum,
        "typical_latch_to_latch": typical,
        "maximum_input_to_latch": input_path,
        "maximum_latch_to_predicate_reset": reset_path,
        "estimated_model_fmax_ghz":
            1000 * (1 - margin_fraction) /
            max(maximum["delay_ps"] + setup,
                reset_path["delay_ps"] + reset_recovery),
        "clock_tree": tree,
        "physical_macros": macros,
        "physical_memory_macros": {
            name: sum(cell["type"] == name
                      for cell in module["cells"].values())
            for name in MEMORY_CELLS
        },
        "targets": targets,
    }
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(output, indent=2) + "\n")
    summary = ", ".join(
        f"{target['frequency_ghz']:g}GHz={'PASS' if target['target_pass'] else 'FAIL'}"
        for target in targets
    )
    print(f"{summary}; report: {output_path}")
    if args.require_model_pass and any(not target["target_pass"]
                                       for target in targets):
        raise SystemExit(1)
    if args.require_pass and (not output["timing_is_signoff"] or
                              any(not target["target_pass"]
                                  for target in targets)):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
