#!/usr/bin/env python3
"""Validate that the production-test strategy covers every retained cell."""

import json
from pathlib import Path


def main():
    root = Path(__file__).resolve().parents[1]
    cells = set(json.loads((root / "photonic/cells.json").read_text())["cells"])
    plan = json.loads((root / "physical/dft.json").read_text())
    covered = set()
    for section in ("scan", "memory_bist", "macro_bist"):
        assigned = plan[section]["cells"]
        assert len(assigned) == len(set(assigned)), f"duplicate {section} cells"
        assert not covered.intersection(assigned), "cell assigned to multiple DFT methods"
        covered.update(assigned)
    assert covered == cells, f"DFT coverage mismatch: missing={cells-covered}, extra={covered-cells}"
    targets = plan["coverage_targets_percent"]
    assert all(0 < value <= 100 for value in targets.values())
    assert plan["access"]["transport"] and plan["release_evidence"]
    print(f"PASS: DFT strategy covers all {len(cells)} retained physical cells")


if __name__ == "__main__":
    main()
