#!/usr/bin/env python3
"""Stop synthesis before WSL runs out of memory or invokes crash capture."""
import argparse
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--memory-mb", type=int, default=10240)
args, yosys_args = parser.parse_known_args()
if args.memory_mb < 256:
    parser.error("--memory-mb must be at least 256")
limit = args.memory_mb * 1024
margin = min(1024 * 1024, limit // 10)
def memory_info():
    return {line.split()[0].rstrip(":"): int(line.split()[1])
            for line in Path("/proc/meminfo").read_text().splitlines()}
reserve = min(3 * 1024 * 1024, memory_info()["MemTotal"] // 5)
job = subprocess.Popen(["prlimit", f"--as={limit * 1024}", "--core=0", "--", "yosys", *yosys_args],
                       start_new_session=True)
try:
    while job.poll() is None:
        try:
            status = Path(f"/proc/{job.pid}/status").read_text()
            size = next(int(line.split()[1]) for line in status.splitlines() if line.startswith("VmSize:"))
            if size > limit - margin or memory_info()["MemAvailable"] < reserve:
                print("Synthesis stopped at the memory guard; completed checkpoints are retained.", file=sys.stderr)
                sys.exit(124)
        except (FileNotFoundError, ProcessLookupError, StopIteration):
            pass
        time.sleep(0.1)
    sys.exit(job.returncode)
finally:
    if job.poll() is None:
        os.killpg(job.pid, signal.SIGTERM)
        try:
            job.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(job.pid, signal.SIGKILL)
            job.wait()
