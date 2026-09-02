# Project Progress

Repository-owned architecture and research-model work is implemented. Current
RTL passes its targeted qualification gates; a from-scratch aggregate replay is
the remaining reproducibility check and is blocked on an unavailable local
Docker daemon. Production release remains blocked on vendor characterization
and physical implementation.

Verified during this closure pass:

- The complete non-clean `make check` aggregate passes on the current worktree.
- ACT4 remains at 281/281 tests.
- Sail/RVFI matches 52,464 retirements across integer, atomic, floating-point,
  memory, privilege, trap, interrupt, FP-state, and CSR coverage.
- Berkeley SoftFloat passes 6,111 comparisons across f32/f64 arithmetic, all
  FMA signs, comparisons, conversions, all rounding modes, special values, and
  exception flags.
- Structural CDC/RDC analysis passes with nine two-flop synchronizers, 15
  TAP-only asynchronous-reset banks, and synchronous core reset handling.
- Control, PMP, five partitioned safety proofs, and an eight-cycle integrated
  pipeline/commit proof with formal cache/MMU interface models pass.
- RTL-to-mapped Yosys/ABC combinational equivalence passes.
- PraxisOS boots through M mode into its supervisor kernel, enables Sv32,
  reaches U mode, runs a user process, and passes in 2,438,493 cycles.
- Upstream OpenOCD drives the Verilated JTAG port to discover the RV32 hart and
  MISA, halt it, write/read `a0`, and resume it.
- The DFT strategy checker covers all 18 retained physical cell types through
  scan, memory BIST, or macro BIST/optical loopback.
- The recorded toolchain check matches ten tools and four pinned source trees.
- Lint passes with zero warnings; imported-IP exceptions remain scoped in
  `rtl/lint.vlt`, and the formal-only CSR visibility wire has one local waiver.
- The paired mapped gate checks 82,494 four-state signals after reset, then
  reuses functional hard-macro models to complete the compiler-workload
  signature rather than checking only PC progress.

Current regenerated physical/timing artifact:

| Metric | Result |
| --- | ---: |
| LUT3s | 16,383 |
| Soft state cells | 3,402 |
| Inserted splitters | 32,122 |
| Inserted regenerators | 25,096 |
| Maximum latch-to-latch delay | 7.965 ps |
| Estimated model Fmax | 103.35 GHz |
| 100 GHz model slack | 0.285 ps |
| Physical preflight blockers | 33 vendor/PDK blockers |

## Repository-owned work

- [x] Restore full ACT4 F/D conformance with the CSR pipeline interlock.
- [x] Make `make clean` remove the real `build/` outputs.
- [x] Regenerate `README.md` and the signoff report after the final remap.
- [x] Make `architecture-cert` depend on `check`.
- [x] Make `release-check` depend on `architecture-cert`, timing signoff, and
      physical release.
- [x] Fix preflight's symbol-rate checks for clocked macros.
- [x] Require all 18 retained physical cell types in preflight.
- [x] Insert connected, balanced splitter trees and loss-driven regenerators in
      the repository-owned physical netlist.
- [x] Integrate `constraints/photonic.sdc` into timing and replace the zero
      interface-delay placeholders with 1 ps constraints.
- [x] Resolve or explicitly waive lint warnings; core-side reset handling is
      synchronous and imported-IP exceptions are scoped in `rtl/lint.vlt`.
- [x] Replace the source-text CDC check with structural CDC/RDC/reset analysis.
- [x] Complete RTL-to-mapped-netlist equivalence qualification with Yosys/ABC
      CEC.
- [x] Make mapped simulation verify workload signatures, not merely X/Z
      cleanliness and PC progress.
- [x] Expand Sail/RVFI beyond one `I-add` program and compare memory, privilege,
      traps, interrupts, FP state, and CSRs.
- [x] Add formal checks for precise traps, handshake stability, killed
      retirement, store issuance, `x0`, cache validity, PMP/MMU, and LR/SC.
- [x] Complete the partitioned safety and integrated top-level formal runs.
- [x] Expand randomized SoftFloat coverage to FMA, conversions, comparisons,
      NaNs, infinities, signed zero, subnormals, dynamic rounding, and all flags.
- [x] Boot and qualify a real Sv32 supervisor OS.
- [x] Complete external OpenOCD interoperability against the Debug Module's
      implemented halt, abstract register-access, CSR discovery, and resume
      profile. Optional program-buffer/system-bus memory access is out of scope.
- [x] Define DFT/scan access and production test strategy for every retained
      physical cell type.
- [ ] Reproduce every gate from a clean checkout. Tool/source locks and the
      `reproduce-check` target are implemented, but this machine has the Docker
      CLI without a running daemon and therefore cannot recreate ACT4/Sail
      artifacts after `make clean`.

## Vendor and physical implementation

- [ ] Obtain SiN/TFLN/InP—and retained PCM—PDKs and verification decks.
- [ ] Vendor-characterize timing, loss, rate, extinction, recovery, tuning,
      PVT, and thermal behavior.
- [ ] Provide physical GDS/models for LUT, state, memory, PC, PMP,
      multiply/divide, and FPU macros.
- [ ] Implement actual dual-rail expansion and 32-channel WDM routing.
- [ ] Physically insert splitters, regenerators, crossings, delay trims, rings,
      and couplers.
- [ ] Implement and characterize the 100 GHz optical clock tree, power delivery,
      skew, jitter, and calibration.
- [ ] Place all five chiplets and define coupling tolerances.
- [ ] Generate the interposer plus five chiplet GDS files.
- [ ] Perform extracted timing, loss, receiver-margin, crosstalk, thermal,
      coupling-tolerance, and Monte Carlo analysis.
- [ ] Obtain clean DRC and connectivity results.
- [ ] Produce `physical/signoff.json` with the required measured fields.
- [ ] Pass `make timing-signoff`, `make physical-release`, and finally
      `make release-check`.

Skipped: 120 GHz optimization, multicore, DMA coherency, vector, and hypervisor
work—they remain explicitly outside the release target.
