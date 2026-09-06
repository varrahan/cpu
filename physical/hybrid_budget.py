#!/usr/bin/env python3
"""Compare source-owned WDM lanes without inventing a CPU clock or PHY data."""
import argparse
import json
import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def message_bits():
    source = (ROOT / "rtl/top/hybrid_pkg.sv").read_text()
    body = source.split("typedef struct packed {", 1)[1].split("} message_t;", 1)[0]
    return sum(math.prod(int(a) - int(b) + 1 for a, b in
                         re.findall(r"\[(\d+):(\d+)\]", field)) or 1
               for field in body.split(";") if "logic " in field)


def compare(config, rate=None, cpu_frequencies=()):
    bits = message_bits()
    for key in ("data_channels", "credit_channels", "wavelengths_per_waveguide", "queue_depth", "credit_bits"):
        if type(config[key]) is not int or config[key] <= 0:
            raise ValueError(f"{key} must be a positive integer")
    if rate is None:
        rate = config["line_rate_gbps"]
    if rate is not None and (not math.isfinite(rate) or rate <= 0):
        raise ValueError("line rate must be finite and positive")
    traffic = config["four_wide_integer_frames_per_cycle"].values()
    if not traffic or any(type(value) is not int or value < 0 for value in traffic):
        raise ValueError("traffic counts must be nonnegative integers")
    frames = sum(traffic)
    if not frames:
        raise ValueError("traffic must include at least one frame")
    receiver = config["receiver_capacity_gbps"]
    if receiver is not None and (receiver <= 0 or not math.isfinite(receiver)):
        raise ValueError("receiver capacity must be finite and positive")
    required = ["electrical_to_optical_ns", "optical_to_electrical_ns",
                "propagation_ns", "credit_return_ns"]
    delays = [config[key] for key in required]
    for value in delays:
        if value is not None and (not math.isfinite(value) or value < 0):
            raise ValueError("link delays must be finite and nonnegative")
    points = []
    for group in config["group_sizes"]:
        if type(group) is not int or group <= 0:
            raise ValueError("wavelength group sizes must be positive integers")
        wavelengths = config["data_channels"] * group + config["credit_channels"]
        point = {
            "wavelengths_per_data_port": group,
            "total_wavelengths": wavelengths,
            "minimum_waveguides": math.ceil(wavelengths / config["wavelengths_per_waveguide"]),
            "fits_one_waveguide": wavelengths <= config["wavelengths_per_waveguide"],
            "bandwidth_cpu_ghz_per_lane_gbps": min(group / bits, 1 / config["credit_bits"]),
            "bandwidth_cpu_ceiling_ghz": None if rate is None else min(rate * group / bits, rate / config["credit_bits"]),
            "buffer_and_link_cpu_ceiling_ghz": None,
        }
        if rate is not None and all(value is not None for value in delays):
            round_trip_ns = bits / (rate * group) + sum(delays) + config["credit_bits"] / rate
            ceiling = min(point["bandwidth_cpu_ceiling_ghz"], config["queue_depth"] / round_trip_ns)
            if receiver is not None:
                ceiling = min(ceiling, receiver / bits)
            point["buffer_and_link_cpu_ceiling_ghz"] = ceiling
        points.append(point)
    selections = []
    for cpu in cpu_frequencies:
        if cpu <= 0 or not math.isfinite(cpu):
            raise ValueError("CPU frequencies must be finite and positive")
        candidates = [p for p in points if p["buffer_and_link_cpu_ceiling_ghz"] is not None
                      and p["buffer_and_link_cpu_ceiling_ghz"] >= cpu]
        selections.append({
            "cpu_ghz": cpu,
            "smallest_group": min((p["wavelengths_per_data_port"] for p in candidates), default=None),
            "qualification": "modeled transport only; electronic timing and optical power unqualified",
        })
    return {
        "status": config["status"],
        "physical_signoff": False,
        "message_bits_from_rtl": bits,
        "integer_payload_lower_bound_bits_per_cycle": 512,
        "encoded_forward_bits_per_cycle": frames * bits,
        "encoded_credit_bits_per_cycle": frames * config["credit_bits"],
        "unknown_characterization": [key for key, value in config.items()
                                     if value is None and not (key == "line_rate_gbps" and rate is not None)],
        "configurations": points,
        "frequency_selections": selections,
        "limits": ["Four-wide figures assume bank-balanced ready operands and warm instruction-cache hits.",
                   "Two cache-hit loads can complete together; misses and ordered side effects share one outstanding external transaction.",
                   "Source ownership removes writer arbitration; receiver and bank capacity remain finite."],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=ROOT / "photonic/hybrid_fabric.json")
    parser.add_argument("--lane-gbps", type=float)
    parser.add_argument("--cpu-ghz", type=float, nargs="*", default=[])
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        result = compare(json.loads(args.config.read_text()), args.lane_gbps, args.cpu_ghz)
    except (ValueError, KeyError, TypeError) as error:
        parser.error(str(error))
    rendered = json.dumps(result, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered)
    else:
        print(rendered, end="")


if __name__ == "__main__":
    main()
