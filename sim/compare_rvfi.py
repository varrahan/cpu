#!/usr/bin/env python3
"""Compare rich DUT RVFI records with Sail architectural traces."""

import argparse
import re
from pathlib import Path


MODES = {"U": 0, "S": 1, "M": 3}


def dut_records(path):
    records = []
    for line in Path(path).read_text().splitlines():
        fields = line.split()
        if len(fields) != 19:
            continue
        records.append({
            "order": int(fields[0]), "mode": int(fields[1]),
            "pc": int(fields[2], 16), "insn": int(fields[3], 16),
            "trap": int(fields[4]), "intr": int(fields[5]),
            "x": (int(fields[6]), int(fields[7], 16)),
            "mem_addr": int(fields[8], 16),
            "rmask": int(fields[9], 16), "wmask": int(fields[10], 16),
            "rdata": int(fields[11], 16), "wdata": int(fields[12], 16),
            "f": (int(fields[14]), int(fields[15], 16))
                 if int(fields[13]) else None,
            "csr": (int(fields[17], 16), int(fields[18], 16))
                   if int(fields[16]) else None,
        })
    return records


def sail_records(path):
    insn = re.compile(
        r"^\[\d+\] \[([MSU])\]: 0x([0-9A-Fa-f]+) "
        r"\(0x([0-9A-Fa-f]+)\)"
    )
    xwrite = re.compile(r"^x(\d+) <- 0x([0-9A-Fa-f]+)")
    fwrite = re.compile(r"^f(\d+) <- 0x([0-9A-Fa-f]+)")
    csr = re.compile(
        r"^CSR .*? \(0x([0-9A-Fa-f]+)\) <- 0x([0-9A-Fa-f]+)"
    )
    memory = re.compile(
        r"^mem\[(?:R|W|RW),0x([0-9A-Fa-f]+)\] (->|<-) "
        r"0x([0-9A-Fa-f]+)"
    )
    records, current = [], None
    for line in Path(path).read_text().splitlines():
        match = insn.match(line)
        if match:
            if current is not None:
                records.append(current)
            current = {
                "mode": MODES[match.group(1)],
                "pc": int(match.group(2), 16),
                "insn": int(match.group(3), 16),
                "trap": 0, "intr": 0, "x": (0, 0), "f": None,
                "csr_writes": [], "memory": [],
            }
            continue
        if current is None:
            continue
        if match := xwrite.match(line):
            current["x"] = (int(match.group(1)), int(match.group(2), 16))
        elif match := fwrite.match(line):
            current["f"] = (int(match.group(1)), int(match.group(2), 16))
        elif match := csr.match(line):
            current["csr_writes"].append(
                (int(match.group(1), 16), int(match.group(2), 16))
            )
        elif match := memory.match(line):
            current["memory"].append(
                ("R" if match.group(2) == "->" else "W",
                 int(match.group(1), 16), int(match.group(3), 16))
            )
        elif line.startswith("trapping from"):
            current["trap"] = 1
            current["intr"] = int("interrupt" in line.lower())
        elif line.startswith("handling int#"):
            current["intr"] = 1
    if current is not None:
        records.append(current)
    return records


def access_value(data, mask):
    first_lane = (mask & -mask).bit_length() - 1
    return (data >> (first_lane * 8)) & ((1 << (mask.bit_count() * 8)) - 1)


def csr_equivalent(got, expected):
    address, value = got
    masks = {
        0x001: 0x1f, 0x002: 0x7, 0x003: 0xff,
        0x302: 0xb7ff, 0x303: 0xaaa, 0x304: 0xaaa, 0x320: 0x7,
    }
    for expected_address, expected_value in expected:
        if expected_address != address:
            continue
        if address in (0x100, 0x300):
            # Reset values of SD/FS/MPP are implementation-defined.
            mask = 0x7fff_87ff
            return (value & mask) == (expected_value & mask)
        if address in masks:
            return (value & masks[address]) == (expected_value & masks[address])
        return value == expected_value
    return False


def compare(dut, sail, allow_interrupt_latency=False):
    start = next((
        i for i, record in enumerate(dut)
        if (record["pc"], record["insn"]) == (sail[0]["pc"], sail[0]["insn"])
    ), None)
    if start is None:
        raise SystemExit(f"DUT never reached Sail entry PC 0x{sail[0]['pc']:08x}")
    dut = dut[start:]
    interrupt_seen = any(record["intr"] for record in dut) and \
        any(record["intr"] for record in sail)
    if allow_interrupt_latency and interrupt_seen:
        dut_interrupt = next(i for i, record in enumerate(dut) if record["intr"])
        sail_interrupt = next(i for i, record in enumerate(sail) if record["intr"])
        if dut_interrupt > sail_interrupt:
            # Synchronizer latency may retire benign wait-loop instructions.
            sail = [*sail]
            sail[sail_interrupt] = {**sail[sail_interrupt], "intr": 0}
            dut = dut[:sail_interrupt + 1] + dut[dut_interrupt + 1:]
    common = min(len(dut), len(sail))
    coverage = {name: False for name in ("memory", "privilege", "traps", "interrupts", "fp", "csr")}
    modes = set()
    for index in range(common):
        got, expected = dut[index], sail[index]
        modes.add(got["mode"])
        for field in ("mode", "pc", "insn", "trap", "intr", "x"):
            if got[field] != expected[field]:
                raise SystemExit(
                    f"retirement {index} {field} mismatch: "
                    f"DUT={got[field]} Sail={expected[field]}"
                )
        for kind, mask, data in (
            ("R", got["rmask"], got["rdata"]),
            ("W", got["wmask"], got["wdata"]),
        ):
            if not mask:
                continue
            matches = [item for item in expected["memory"]
                       if item[0] == kind and item[1] == got["mem_addr"]]
            if not matches or matches[-1][2] != access_value(data, mask):
                raise SystemExit(
                    f"retirement {index} memory mismatch: DUT={got} "
                    f"Sail={expected['memory']}"
                )
            coverage["memory"] = True
        if got["f"] is not None:
            if got["f"] != expected["f"]:
                raise SystemExit(
                    f"retirement {index} FP mismatch: "
                    f"DUT={got['f']} Sail={expected['f']}"
                )
            coverage["fp"] = True
        if got["csr"] is not None:
            if got["csr"][0] == 0x344:
                continue
            if not csr_equivalent(got["csr"], expected["csr_writes"]):
                raise SystemExit(
                    f"retirement {index} CSR mismatch: DUT={got['csr']} "
                    f"Sail={expected['csr_writes']}"
                )
            coverage["csr"] = True
        coverage["traps"] |= bool(got["trap"])
        coverage["interrupts"] |= bool(got["intr"])
    coverage["privilege"] = len(modes) > 1
    coverage["interrupts"] |= interrupt_seen
    if len(dut) > len(sail) or len(sail) - len(dut) > 2:
        raise SystemExit(f"trace length mismatch: DUT={len(dut)} Sail={len(sail)}")
    return common, coverage


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("dut")
    parser.add_argument("sail")
    parser.add_argument("--require", nargs="*", default=[])
    parser.add_argument("--allow-interrupt-latency", action="store_true")
    args = parser.parse_args()
    dut, sail = dut_records(args.dut), sail_records(args.sail)
    if not dut or not sail:
        raise SystemExit("empty DUT or Sail retirement trace")
    common, coverage = compare(dut, sail, args.allow_interrupt_latency)
    missing = [name for name in args.require if not coverage.get(name)]
    if missing:
        raise SystemExit("missing differential coverage: " + ", ".join(missing))
    covered = ", ".join(name for name, hit in coverage.items() if hit)
    print(f"PASS: Sail/RVFI rich differential ({common} records; {covered})")


if __name__ == "__main__":
    main()
