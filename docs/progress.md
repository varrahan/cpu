# Project Progress

Repository-owned RTL and research-model work is implemented. Current RTL passes
its local qualification gates and the full configured ACT4/Sail replay. A
from-scratch aggregate replay has not been run in this worktree. Production
release remains blocked on vendor characterization and physical implementation.

Verified during this closure pass:

- The complete non-clean `make check` aggregate passes on the current worktree.
- ACT4 passes all 660 tests selected by the complete CPU-owned configuration.
- Sail/RVFI matches 56,989 retirements across integer, atomic, floating-point,
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
- The paired mapped gate checks every mapped leaf-cell signal after reset, then
  reuses functional hard-macro models to complete the compiler-workload
  signature rather than checking only PC progress.

Current regenerated physical/timing artifact:

| Metric | Result |
| --- | ---: |
| LUT3s | 16,834 |
| Soft state cells | 3,423 |
| Inserted splitters | 32,757 |
| Inserted regenerators | 25,940 |
| Maximum latch-to-latch delay | 8.125 ps |
| Estimated model Fmax | 101.59 GHz |
| 100 GHz model slack | 0.125 ps |
| Physical preflight blockers | 35 implementation/vendor blockers |

## Repository-owned work

- [x] Restore full ACT4 F/D conformance with the CSR pipeline interlock.
- [x] Remove the ACT4 extension whitelist so privileged tests are selected from
      the complete CPU-owned architecture configuration.
- [x] Correct PMP WARL behavior, writable interrupt-pending state, interrupt
      target priority, SRET MPRV clearing, and WFI wake behavior.
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
- [x] Reproduce every gate from an empty build directory. `reproduce-check`
      verified the pinned tools and sources, regenerated the test artifacts,
      and passed the complete architecture certification.
- [x] Run the unfiltered ACT4 configuration and resolve all 660 selected tests.

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
