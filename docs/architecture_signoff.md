# Architecture and clock feasibility status

## Architecture verification

`make architecture-cert` is the reproducible architecture gate. It combines
the baseline checks, end-to-end and directed architecture regressions, formal
control proof, whole-design lint, structural CDC policy, JTAG debug transport,
official ACT4 tests, Sail/RVFI differential retirement, randomized SoftFloat
comparison, and machine-to-supervisor Sv32 boot.

| Gate | Result |
| --- | --- |
| Baseline `make check` and `make architecture-check` | Pass |
| ACT4 supported ISA | 281/281 pass |
| Sail/RVFI differential | 4,361 retirements match |
| Berkeley SoftFloat randomized comparison | 4,000 cases pass |
| Machine-to-supervisor Sv32 boot | Pass in 11,671 cycles |
| RISC-V Debug 1.0 JTAG DTM/minimal DM regression | Pass |
| Interrupt, JTAG DMI, and reset structural CDC policy | Pass |
| Whole-design Verilator lint | Pass with non-fatal warnings |

The ACT4 configuration is CPU-owned in
`sim/act4/photonic-rv32gc.yaml` and covers `I`, `M`, `F`, `D`, `Zicsr`,
`Zifencei`, `Zca`, `Zcf`, `Zcd`, `Zaamo`, and `Zalrsc`. ACT4 is pinned at
commit `1cb285fe70ecc375422d2a72b7b5183a9f0ea771` and container digest
`sha256:6c1967e40bb17ef23b9a175529882128dd04d76990f13fafa7c9756bac761a77`.
Berkeley SoftFloat is pinned at commit
`a0c6494cdc11865811dec815d5c0049fba9d82a8`.

Coverage includes the implemented `RV32GC`/`ILP32D` instruction set, integer
and floating-point state, LR/SC and AMOs, precise traps, M/S/U privilege,
delegation, vectored interrupts, WFI, PMP, Sv32 translation/page faults, cache
behavior, memory backpressure, and halt/resume/register access.

The end-to-end test now includes a compiler-produced freestanding workload,
not only hand-encoded instruction fragments. Its sorting, CRC32, 3x3 matrix,
GCD, atomic, CSR, integer, and floating-point signatures are checked in memory.
The linked image gate requires 117 base/M/A/Zicsr/F/D mnemonics and contains
160 compressed instructions. The mapped four-state run executes the same image
for 1,024 cycles and rejects any X/Z transition at all mapped cell boundaries.

This completes the repository architecture-certification gate; it is not a
third-party RISC-V certification certificate. Production release still needs
vendor CDC/RDC analysis, a full OS boot and software qualification campaign,
external debugger interoperability against a complete Debug Module, DFT/scan,
and physical implementation signoff. The included CDC check is structural,
the boot image is a focused M/S/Sv32 program rather than an OS, and the JTAG
block is a minimal Debug 1.0 transport/module implementation.

## Preliminary mapped timing

`make timing-check` traces the mapped LUT/state graph and the explicit PC,
PMP, multiply/divide, and floating-point macros using the 100 GHz research
contract in `photonic/cells.json`. It assumes 2 ps optical pulses, 10% clock
uncertainty, and 5% skew; the margins remain calibration knobs for extracted
signoff. `make timing-signoff` additionally requires vendor-characterized
models.

Conventional coarse synthesis, width reduction, FSM/peephole optimization,
resource sharing, removal of writes to invalid cache tags, and sharing debug
read ports reduced the soft map before memory inference. Mapping the integer
and FP register files plus cache tag/data arrays to six parameterized memory
macros removed the remaining storage read-mux trees.

| Mapped resource | Before | Optimized | Change |
| --- | ---: | ---: | ---: |
| `P_CHI2_LUT3` | 55,162 | 16,253 | -70.5% |
| Soft state cells | 11,381 | 3,382 | -70.3% |
| Photonic memory macros | 0 | 6 | +6 |

| Measurement | Result |
| --- | ---: |
| Longest structural data path | 48 LUT/memory/regenerator levels |
| Longest structural predicate-reset path | 51 levels |
| Worst data path including regeneration | 7.450 ps before setup/margins |
| Worst predicate-reset path | 7.295 ps before recovery/margins |
| Research-model estimated Fmax | 110.39 GHz |
| 100 GHz data slack | +0.800 ps |
| 100 GHz predicate-reset slack | +1.005 ps |
| Exploratory 120 GHz data slack | -0.617 ps (fail) |
| Standalone worst-path regenerators | 27 |
| Clocked state cells and macros | 3,391 |
| Balanced clock-tree depth | 12 splitter levels |
| Splitters | 3,390 |
| Modeled regenerated clock-tree delay | 0.420 ps |

These numbers are structural estimates and may include false paths; they are
not extracted signoff. They establish that the complete mapped graph meets the
100 GHz cell contract, not that a manufacturable PIC meets it.

At 100 GHz the optimized clock tree and margins leave the 7.450 ps worst data
path with 0.800 ps slack. Predicate-reset recovery independently closes with
1.005 ps slack. The model limits unregenerated loss to 8 dB and inserts 27
standalone regenerators on the worst data path.

`make known-state-check` complements the architectural tests with a four-state
simulation of the mapped CPU. After deterministic reset, all 81,868 mapped
leaf-cell signals and external outputs are binary. The structural contract also
rejects X/Z constants and undriven or multiply driven nets. This guarantee
requires driven external inputs and completion of the documented reset edge;
power-up behavior before reset remains a platform responsibility.

The logical clock cells and macros are contract-rated above 100 GHz. The
12-level tree requires four path regenerators and has 0.420 ps modeled delay
before extracted routing and coupling. Receiver threshold, source power,
regenerator gain, GDS cells, PVT/thermal behavior, and extracted skew/loss
remain uncharacterized. Consequently `make timing-check` passes while
`make timing-signoff` and `make release-check` correctly fail.
