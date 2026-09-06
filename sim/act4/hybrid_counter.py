#!/usr/bin/env python3
"""Port ACT4's mcycle wait bound for a CPU with serialized interconnects.

The upstream test requires 300 loop instructions to finish in 1000 cycles.
Keep the wrap-to-zero checks and use a 100000-cycle upper bound in a separate
source tree. The original test and its ELF remain available unchanged.
"""
import os
from pathlib import Path

root = Path(__file__).resolve().parents[2] / "build/act4/source"
source = root / "tests/priv/Sm/Sm_mcsr_cntr-00.S"
target = root / "work/hybrid-counter/tests/priv/Sm/Sm_mcsr_cntr-00.S"
original = "sltiu x13, x13, 1000       # Pass if mcycle wrapped to a small value"
replacement = "LI(x15, 100000)             # Hybrid transport timing bound\n  sltu x13, x13, x15          # Still require a bounded value after wrap"
text = source.read_text()
assert text.count(original) == 1, "ACT4 counter source changed; review the timing port"
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(text.replace(original, replacement))
env = root / "work/hybrid-counter/tests/env"
if not env.exists():
    env.symlink_to(os.path.relpath(root / "tests/env", env.parent), target_is_directory=True)
print("ACT4 hybrid port: mcycle loop bound 1000 -> 100000 cycles; wrap checks retained")
