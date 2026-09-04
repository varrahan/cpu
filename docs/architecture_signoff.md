# Architecture and clock feasibility status

## Architecture verification

`make architecture-cert` is the reproducible architecture gate. It combines
the baseline checks, end-to-end and directed architecture regressions, formal
proofs, whole-design lint, structural CDC policy, internal and OpenOCD-driven
JTAG debug, official ACT4 tests, Sail/RVFI differential retirement, randomized
SoftFloat comparison, focused machine-to-supervisor boot, and a PraxisOS Sv32
supervisor/user boot.

| Gate | Result |
| --- | --- |
| Baseline `make check` and `make architecture-check` | Pass |
| Whole-design lint | Pass with zero warnings |
| Interrupt, JTAG DMI, and reset structural CDC policy | Pass |
| Control, PMP, partitioned safety, and modeled-interface integrated-top formal | Pass |
| RISC-V Debug 1.0 JTAG DTM/DM regression | Pass |
| External OpenOCD halt, XLEN/MISA discovery, GPR access, resume | Pass |
| ACT4 | 660/660 complete configured tests pass |
| Sail/RVFI differential | 56,989 retirements match |
| Berkeley SoftFloat randomized comparison | 6,111 cases pass |
| Machine-to-supervisor Sv32 boot | Pass in 9,538 cycles |
| PraxisOS supervisor/user Sv32 boot | Pass in 2,438,493 cycles |
| Architecture-cert constituent gates | Local gates, ACT4, and Sail replay pass |

The ACT4 configuration is CPU-owned in
`sim/act4/photonic-rv32gc.yaml`. Generation now uses its complete extension
list, including M/S/U privilege and Sv32, rather than the old non-privileged
extension whitelist. The complete configured run passes 660/660 tests. ACT4 is pinned at
commit `1cb285fe70ecc375422d2a72b7b5183a9f0ea771` and container digest
`sha256:6c1967e40bb17ef23b9a175529882128dd04d76990f13fafa7c9756bac761a77`.
Berkeley SoftFloat is pinned at commit
`a0c6494cdc11865811dec815d5c0049fba9d82a8`. PraxisOS is pinned at commit
`277bd2b21124722209b93af3ec82ea182a22d79c`; OpenOCD is pinned at commit
`9ea7f3d647c8ecf6b0f1424002dfc3f4504a162c`.

The core interlocks decode while a CSR instruction is in EX/MEM, ensuring
updates such as `mstatus.FS`, `frm`, and `fflags` commit before a following
floating-point or CSR instruction executes.

Coverage includes the implemented `RV32GC`/`ILP32D` instruction set, integer
and floating-point state, LR/SC and AMOs, precise traps, M/S/U privilege,
delegation, vectored interrupts, WFI, PMP, Sv32 translation/page faults, cache
behavior, memory backpressure, and halt/resume/register access.

The pinned PraxisOS qualification boots through a small machine-mode firmware,
enters its supervisor kernel, installs Sv32 page tables, reaches user mode, runs
a user process, and exits through the platform pass address. This exercises a
real supervisor OS rather than only the focused boot image.

The external debug gate connects upstream OpenOCD to the Verilated `top_jtag`
over remote bitbang. OpenOCD discovers the 32-bit hart and MISA, halts it,
writes and reads `a0`, and resumes execution. The implemented profile has no
program buffer, so OpenOCD reports that optional memory-consistency fence
execution is unavailable; halt and abstract register access remain qualified.

The end-to-end test now includes a compiler-produced freestanding workload,
not only hand-encoded instruction fragments. Its sorting, CRC32, 3x3 matrix,
GCD, atomic, CSR, integer, and floating-point signatures are checked in memory.
The linked image gate requires 117 base/M/A/Zicsr/F/D mnemonics and contains
160 compressed instructions. The mapped four-state run observes all mapped cell
boundaries for 1,024 cycles. A second mapped run reuses the behavioral hard-
macro models, completes the same image, and checks its full memory signature.

The corrected RTL passes every locally runnable architecture gate, but this is
not a third-party RISC-V certification certificate. Production release still
needs vendor CDC/RDC, device
characterization, and physical implementation signoff. The included CDC check
is structural and the debug profile deliberately omits optional
program-buffer/system-bus memory access.

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
| `P_CHI2_LUT3` | 55,162 | 16,834 | -69.5% |
| Soft state cells | 11,381 | 3,423 | -69.9% |
| Photonic memory macros | 0 | 6 | +6 |

| Measurement | Result |
| --- | ---: |
| Worst-delay structural data path | 174 LUT/memory/regenerator levels |
| Reset-pin state cells | 0; reset timing is synchronous data timing |
| Worst data path including regeneration | 8.125 ps before setup/margins |
| Research-model estimated Fmax | 101.59 GHz |
| 100 GHz data slack | +0.125 ps |
| Exploratory 120 GHz data slack | -1.458 ps (fail) |
| Required worst data-path regenerators | 30 |
| Clocked state cells and macros | 3,432 |
| Balanced clock-tree depth | 12 splitter levels |
| Clock-tree splitters | 3,431 |
| Modeled regenerated clock-tree delay | 0.570 ps |

These numbers are structural estimates and may include false paths; they are
not extracted signoff. They establish that the complete mapped graph meets the
100 GHz cell contract, not that a manufacturable PIC meets it.

At 100 GHz the optimized clock tree and margins leave the 8.125 ps worst data
path with 0.125 ps slack. The current map has no reset-pin state cells; all
reset behavior is synchronous and is therefore covered by ordinary data-path
timing. The model limits unregenerated loss to 8 dB and requires 30
regenerations on the worst path. The repository-owned physical netlist now
contains all 25,940 loss-driven regenerators and 32,757 required splitters, but
remains single-rail and lacks WDM routing. Vendor implementation and
characterization remain outstanding.

`make known-state-check` complements the architectural tests with a four-state
simulation of the mapped CPU. After deterministic reset, all mapped leaf-cell
signals and external outputs are binary. The structural contract also
rejects X/Z constants and undriven or multiply driven nets. This guarantee
requires driven external inputs and completion of the documented reset edge;
power-up behavior before reset remains a platform responsibility.

The logical clock cells and macros are contract-rated above 100 GHz. The
12-level tree requires six path regenerators and has 0.570 ps modeled delay
before extracted routing and coupling. Receiver threshold, source power,
regenerator gain, GDS cells, PVT/thermal behavior, and extracted skew/loss
remain uncharacterized. Consequently `make timing-check` passes while
`make timing-signoff` and `make release-check` correctly fail.
