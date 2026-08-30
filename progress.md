# Project Progress

The lint cleanup from the previous audit is complete. The open RTL flow still
works; production release remains blocked.

Current verification:

- `make check`: passes.
- `make architecture-cert`: passes; ACT4 remains 281/281.
- `make timing-signoff`: fails because models are not vendor-characterized.
- Physical preflight: 27 blockers.
- Working tree: 9 modified, 1 deleted, 51 untracked files.
- Lint: passes with zero warnings; local issues were fixed and imported-IP
  warnings are explicitly scoped in `rtl/lint.vlt`.

A new finding: regenerated timing is deterministic but no longer matches
`docs/architecture_signoff.md`.

| Metric | Documented | Current |
| --- | ---: | ---: |
| LUT3s | 16,253 | 16,209 |
| Soft state cells | 3,382 | 3,397 |
| Data-path levels | 48 | 57 |
| Reset-path levels | 51 | 56 |
| Estimated Fmax | 110.39 GHz | 107.59 GHz |
| Data slack | 0.800 ps | 0.665 ps |
| Reset slack | 1.005 ps | 0.600 ps |

## Repository-owned work

- [ ] Review and commit the entire current implementation.
- [ ] Confirm and stage deletion of `constraints/constraint.xdc`.
- [ ] Remove obsolete tracked simulation artifacts and make `make clean` clean
      the real build outputs.
- [ ] Investigate the changed timing/map results, then regenerate `README.md`
      and the signoff report from the final netlist.
- [ ] Make `architecture-cert` depend on `check`; currently it omits photonic,
      known-state, preflight, and timing checks.
- [ ] Make `release-check` depend on `architecture-cert`; currently release can
      skip ACT4, Sail, SoftFloat, CDC, lint, JTAG, and boot qualification.
- [ ] Fix preflight's incorrect symbol-rate checks for clocked macros.
- [ ] Require all retained physical support cells in preflight, not only the
      eight logical mapped types.
- [ ] Require actual splitter/regenerator insertion. Preflight currently
      estimates 31,918 splitters and reports `inserted_regenerators: null`.
- [ ] Integrate `constraints/photonic.sdc` into the timing flow and replace its
      zero interface-delay placeholders.
- [x] Resolve or explicitly waive lint warnings; core-side reset handling is
      synchronous and imported-IP exceptions are scoped in `rtl/lint.vlt`.
- [ ] Replace the source-text CDC check with real CDC/RDC/reset analysis.
- [ ] Add RTL-to-mapped-netlist equivalence checking.
- [ ] Make mapped simulation verify workload signatures, not merely X/Z
      cleanliness and PC progress.
- [ ] Expand Sail/RVFI beyond one `I-add` program and compare memory, privilege,
      traps, interrupts, FP state, and CSRs.
- [ ] Add formal checks for precise traps, handshake stability, killed
      retirement, store issuance, `x0`, cache validity, PMP/MMU, and LR/SC.
- [ ] Expand randomized SoftFloat coverage to FMA, conversions, comparisons,
      NaNs, infinities, signed zero, subnormals, dynamic rounding, and all flags.
- [ ] Boot and qualify a real Sv32 supervisor OS.
- [ ] Complete external debugger interoperability against a complete Debug
      Module.
- [ ] Define DFT/scan access and production test strategy.
- [ ] Reproduce every gate from a clean checkout with recorded tool versions.

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
