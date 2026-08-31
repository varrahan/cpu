# Project Progress

The baseline RTL, architecture-conformance, and research timing gates pass.
Production release remains blocked.

Current verification:

- `make check`: passes.
- `make architecture-cert`: passes; ACT4 is 281/281, Sail/RVFI matches 4,361
  retirements, SoftFloat passes 4,000 cases, and Sv32 boot passes.
- `make timing-check`: passes the 100 GHz research model.
- `make timing-signoff`: fails because models are not vendor-characterized.
- Physical preflight: 27 blockers.
- Lint: passes with zero warnings; local issues were fixed and imported-IP
  warnings are explicitly scoped in `rtl/lint.vlt`.
- Known-state check: 81,955 mapped signals remain binary after reset.

Current regenerated backend:

| Metric | Current |
| --- | ---: |
| LUT3s | 16,273 |
| Soft state cells | 3,397 |
| Data-path levels | 55 |
| Reset-path levels | 54 |
| Estimated Fmax | 107.80 GHz |
| 100 GHz data slack | 0.680 ps |
| 100 GHz reset slack | 0.615 ps |

## Repository-owned work

- [x] Restore full ACT4 F/D conformance with the CSR pipeline interlock.
- [ ] Make `make clean` remove the real build outputs.
- [x] Regenerate `README.md` and the signoff report from the current netlist.
- [ ] Make `architecture-cert` depend on `check`; currently it omits photonic,
      known-state, preflight, and timing checks.
- [ ] Make `release-check` depend on `architecture-cert`; currently release can
      skip ACT4, Sail, SoftFloat, CDC, lint, JTAG, and boot qualification.
- [ ] Fix preflight's incorrect symbol-rate checks for clocked macros.
- [ ] Require all retained physical support cells in preflight, not only the
      eight logical mapped types.
- [ ] Require actual splitter/regenerator insertion. Preflight currently
      estimates 31,986 splitters and reports `inserted_regenerators: null`.
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
