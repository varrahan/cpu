# Project Progress

Repository-owned release work is substantially implemented, but the edited RTL
has not yet completed a clean end-to-end qualification run. Production release
also remains blocked on vendor characterization and physical implementation.

Verified during this closure pass:

- ACT4 remains at 281/281 tests.
- Sail/RVFI matches 52,464 retirements across integer, atomic, floating-point,
  memory, privilege, trap, interrupt, FP-state, and CSR coverage.
- Berkeley SoftFloat passes 6,111 comparisons across f32/f64 arithmetic, all
  FMA signs, comparisons, conversions, all rounding modes, special values, and
  exception flags.
- Structural CDC/RDC analysis passes with nine two-flop synchronizers, 15
  TAP-only asynchronous-reset banks, and synchronous core reset handling.
- The control and PMP formal proofs pass. The integrated safety and top-level
  proofs have not completed.
- The DFT strategy checker covers all 18 retained physical cell types through
  scan, memory BIST, or macro BIST/optical loopback.
- The recorded toolchain check matches ten tools and two pinned source trees.
- Lint previously passed with zero warnings; imported-IP exceptions remain
  scoped in `rtl/lint.vlt`.
- Known-state simulation previously kept 81,955 mapped signals binary after
  reset; mapped workload-signature checking is now implemented.

The full `make check`, `make architecture-cert`, and clean `make reproduce-check`
flows still need to be rerun after the final RTL changes.

Last generated physical/timing artifact (regeneration is required because later
RTL edits made this artifact stale):

| Metric | Last generated |
| --- | ---: |
| LUT3s | 16,273 |
| Soft state cells | 3,397 |
| Inserted splitters | 31,986 |
| Inserted regenerators | 24,911 |
| Maximum latch-to-latch delay | 8.020 ps |
| Estimated model Fmax | 102.74 GHz |
| 100 GHz model slack | 0.230 ps |
| Physical preflight blockers | 33 vendor/PDK blockers |

## Repository-owned work

- [x] Restore full ACT4 F/D conformance with the CSR pipeline interlock.
- [x] Make `make clean` remove the real `build/` outputs.
- [ ] Regenerate `README.md` and the signoff report after the final remap; the
      previous generated report no longer describes the edited RTL.
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
- [ ] Complete RTL-to-mapped-netlist equivalence qualification. The Yosys/ABC
      CEC flow is implemented, but its final rerun is pending after the AIG
      symbol-collision fix.
- [x] Make mapped simulation verify workload signatures, not merely X/Z
      cleanliness and PC progress.
- [x] Expand Sail/RVFI beyond one `I-add` program and compare memory, privilege,
      traps, interrupts, FP state, and CSRs.
- [x] Add formal checks for precise traps, handshake stability, killed
      retirement, store issuance, `x0`, cache validity, PMP/MMU, and LR/SC.
- [ ] Complete the integrated safety and top-level formal runs; control and PMP
      currently pass independently.
- [x] Expand randomized SoftFloat coverage to FMA, conversions, comparisons,
      NaNs, infinities, signed zero, subnormals, dynamic rounding, and all flags.
- [ ] Boot and qualify a real Sv32 supervisor OS.
- [ ] Complete external debugger interoperability against a complete Debug
      Module.
- [x] Define DFT/scan access and production test strategy for every retained
      physical cell type.
- [ ] Reproduce every gate from a clean checkout. Tool/source locks and the
      `reproduce-check` target are implemented and validate the current
      environment, but the clean replay has not completed.

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
