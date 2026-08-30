#!/usr/bin/env python3
import re
import sys
from pathlib import Path

def dut_records(path):
    records = []
    for line in Path(path).read_text().splitlines():
        fields = line.split()
        if len(fields) == 8:
            records.append((int(fields[2], 16), int(fields[3], 16),
                            int(fields[6]), int(fields[7], 16)))
    return records

def sail_records(path):
    insn = re.compile(r"^\[\d+\] \[[A-Z]+\]: 0x([0-9A-Fa-f]+) \(0x([0-9A-Fa-f]+)\)")
    write = re.compile(r"^x(\d+) <- 0x([0-9A-Fa-f]+)")
    records, current = [], None
    for line in Path(path).read_text().splitlines():
        match = insn.match(line)
        if match:
            if current is not None: records.append(tuple(current))
            current = [int(match.group(1), 16), int(match.group(2), 16), 0, 0]
            continue
        match = write.match(line)
        if match and current is not None:
            current[2:] = [int(match.group(1)), int(match.group(2), 16)]
    if current is not None: records.append(tuple(current))
    return records

def main():
    dut, sail = dut_records(sys.argv[1]), sail_records(sys.argv[2])
    if not dut or not sail: raise SystemExit("empty DUT or Sail retirement trace")
    start = next((i for i, record in enumerate(dut) if record[0] == sail[0][0]), None)
    if start is None: raise SystemExit(f"DUT never reached Sail entry PC 0x{sail[0][0]:08x}")
    dut = dut[start:]
    common = min(len(dut), len(sail))
    for index in range(common):
        if dut[index] != sail[index]:
            raise SystemExit(f"retirement {index} mismatch: DUT={dut[index]} Sail={sail[index]}")
    if len(dut) > len(sail) or len(sail) - len(dut) > 2:
        raise SystemExit(f"trace length mismatch: DUT={len(dut)} Sail={len(sail)}")
    print(f"PASS: Sail/RVFI retirement differential ({common} records)")

if __name__ == "__main__": main()
