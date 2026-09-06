#!/usr/bin/env python3
import importlib.util
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("budget", root / "physical/hybrid_budget.py")
budget = importlib.util.module_from_spec(spec)
spec.loader.exec_module(budget)
config = json.loads((root / "photonic/hybrid_fabric.json").read_text())
result = budget.compare(config)
assert config["data_channels"] == config["credit_channels"] == 52
assert result["message_bits_from_rtl"] == 307
assert result["encoded_forward_bits_per_cycle"] == 22 * 307
assert not result["physical_signoff"]
assert result["configurations"][0]["minimum_waveguides"] == 4
assert all(p["buffer_and_link_cpu_ceiling_ghz"] is None for p in result["configurations"])
for key in ("electrical_to_optical_ns", "optical_to_electrical_ns", "propagation_ns", "credit_return_ns"):
    config[key] = 0.1
points = budget.compare(config, 100, [0.3, 0.5, 10])
assert [p["smallest_group"] for p in points["frequency_selections"]] == [1, 2, None]
for bad in (0, -1, float("nan"), float("inf")):
    try:
        budget.compare(config, bad)
    except ValueError:
        pass
    else:
        raise AssertionError(f"accepted invalid line rate {bad}")
    try:
        budget.compare({**config, "receiver_capacity_gbps": bad}, None)
    except ValueError:
        pass
    else:
        raise AssertionError(f"accepted invalid receiver capacity {bad} without a line rate")
print("PASS: RTL-sized WDM bandwidth, unknown characterization, capacity boundaries and invalid inputs")
