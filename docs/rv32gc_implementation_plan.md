# RV32GC/ILP32D photonic CPU implementation plan

## Release target

The behavioral architecture target is a little-endian RV32GC hart using the
ILP32D ABI.  `G` expands to `IMAFD_Zicsr_Zifencei`; `C` adds compressed
instructions.  The hart must retain a physical optical state-transition clock
of at least 100 GHz.  Multicycle execution is allowed, but aggregating slower
lanes is not a substitute for the 10 ps state clock.

The production target also includes machine, supervisor and user privilege,
Sv32 address translation, physical memory protection, maskable software,
timer and external interrupts, a non-maskable interrupt, and a ratified-style
external debug boundary.  This is an explicit RV32 platform target: current
RVA23 and RVB23 application profiles are RV64-only.

## Implementation sequence

1. Preserve the existing RV32I regression and mapped photonic flow.
2. Add `M`, `A`, `F`, `D`, `C`, and `Zifencei` decode and execution.
3. Add the 32 by 64-bit floating-point register file, `fcsr`, accrued exception
   flags, dynamic rounding, NaN boxing, and precise FP retirement.
4. Add multibeat `FLD`/`FSD`, atomic memory operations, LR/SC reservation
   invalidation, instruction-cache invalidation, and RVWMO ordering points.
5. Complete interrupt, privilege, delegation, PMP, and Sv32 CSR/state behavior.
6. Add TLB/page-table-walk integration and precise page/access faults.
7. Add halt/resume, abstract register access, single-step, triggers, and a DMI
   boundary without placing the debug transport on the 100 GHz clock tree.
8. Run architectural, randomized IEEE-754, formal/RVFI, mapped-netlist, loss,
   mandatory 100 GHz timing, and exploratory higher-frequency checks.

## Floating-point execution contract

- Support every RV32 `F` and `D` instruction, including fused operations,
  divide, square root, conversions, comparisons, classification, loads, and
  stores.
- Match RISC-V canonical-NaN, signaling-NaN, signed-zero, infinity, subnormal,
  rounding-mode, and accrued `NV/DZ/OF/UF/NX` behavior.
- Use a decoupled, backpressured FPU.  Add/multiply/FMA may be pipelined;
  divide and square root may be iterative.  No FPU combinational path may be
  assumed to fit in one 10 ps cycle.
- Keep FP architectural state optical.  External debug and memory may cross a
  slower asynchronous boundary while the optical hart stalls safely.

## Acceptance

- Compile and run `-march=rv32gc -mabi=ilp32d` programs.
- Pass ACT4 tests for every implemented extension and differential retirement
  against Sail or Spike.
- Compare randomized FP results and flags against Berkeley SoftFloat.
- Boot machine-mode firmware; then boot an RV32 Sv32 supervisor payload.
- Pass lint, formal control properties, CDC/RDC, cache/PMP/MMU tests, and the
  mapped logical-cell regression.
- `make timing-check` must pass at 100 GHz after the complete netlist is
  remapped; 120 GHz remains an optimization target, not a release requirement.
  `make release-check` remains blocked until foundry GDS, extracted
  optical loss/timing, clock power, PVT, DRC, and connectivity are signed off.

Current status: `make check` passes and the complete mapped research model
closes at 100 GHz. Sail/RVFI, SoftFloat, and boot pass; ACT4 passes all 660
tests selected by the complete unfiltered configuration. See the
[architecture/signoff report](architecture_signoff.md).

## Non-RTL release inputs

Foundry PDKs, characterized nonlinear/state macros, package loss, laser and
regenerator power, scan/DFT methodology, SRAM/PCM macros, and fabrication data
cannot be produced by the open RTL flow.  Missing inputs must remain failing
release gates rather than being replaced with research estimates.
