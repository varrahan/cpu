# 100+ GHz strict all-optical RV32GC CPU

## Goal

Implement a 32-bit `RV32GC`/`ILP32D` processor with M/S/U privilege, PMP, Sv32,
interrupts, debug control, split optical L1 caches, and a heterogeneous
SiN/TFLN/InP/PCM implementation flow. CPU data and control remain optical end
to end; electronics are limited to laser power, DC bias, heaters, slow
resonance calibration, and external debug/memory boundaries.

Full-chip GDS release is blocked unless extracted worst-case timing closes at
100 GHz or higher and vendor PDK verification succeeds.

The requirement is a physical optical state-transition clock of at least
100 GHz. WDM channel spacing, aggregate throughput from slower lanes, and
simulation clock parameters do not satisfy it. The five-stage RTL remains the
architectural reference, but the physical backend may add transparent
wave-pipeline boundaries while preserving architectural behavior.

## Execution order

1. Establish passing baseline regressions.
2. Complete RV32I/M-mode behavior and precise pipeline state.
3. Add split L1 caches and external optical-memory handshakes.
4. Add photonic standard cells and Yosys mapping.
5. Replace any mapped cell that cannot switch, regenerate, and cascade inside
   the 10 ps extracted cycle budget.
6. Generate and verify heterogeneous physical layouts.
7. Record measured results and deviations in this document.

## CPU architecture

- Use the existing staged architectural organization with explicit valid,
  stall, kill, and exception state. Resolve branches in execute without a
  predictor to avoid speculative photonic state and fanout.
- Implement RV32I arithmetic, shifts, branches, jumps, loads/stores, `FENCE`,
  `ECALL`, and `EBREAK`; add all six Zicsr instructions and `MRET`.
- Implement precise synchronous traps for illegal instructions, breakpoints,
  ECALL, instruction/load/store misalignment, and external memory errors.
  Misaligned accesses trap rather than split.
- Implement direct-mode `mtvec`, `mstatus`, `misa = 0x40000100`, `mscratch`,
  `mepc`, `mcause`, `mtval`, zero-valued machine identity CSRs, zero-valued
  `mie`/`mip`, `mcycle[h]`, `minstret[h]`, and `mcountinhibit`.
- Implement `M`, `A`, `F`, `D`, `C`, `Zifencei`, vectored interrupts,
  delegation, WFI, M/S/U privilege, PMP, Sv32, and an abstract debug boundary.
- Keep zero, sign, carry/borrow, comparisons, branch-taken, and validity as
  transient internal predicates. RV32I has no architectural flags register.

## L1 caches and external memory

- Add independent 256-byte, direct-mapped I- and D-caches with 16-byte lines,
  16 sets, 24-bit tags, and active-cavity time-bin storage.
- Make the I-cache read-only and the D-cache write-through and
  no-write-allocate. Stores wait for external acknowledgement.
- Fill a cache line using four sequential 32-bit reads. Each port permits one
  outstanding transaction.
- Replace the combinational memory interface with:
  - `imem_req_valid`, `imem_req_ready`, `imem_req_addr`
  - `imem_rsp_valid`, `imem_rsp_ready`, `imem_rsp_rdata`, `imem_rsp_error`
  - `dmem_req_valid`, `dmem_req_ready`, `dmem_req_write`, `dmem_req_addr`,
    `dmem_req_wdata`, `dmem_req_be`
  - `dmem_rsp_valid`, `dmem_rsp_ready`, `dmem_rsp_rdata`, `dmem_rsp_error`
- Stop fetch on an I-cache miss while older stages drain. Hold the faulting and
  younger stages during a D-cache transaction while older writeback retires
  once. Redirects cancel unissued wrong-path fill beats; accepted transactions
  complete and are discarded. Memory errors invalidate partial fills and raise
  precise access faults.

## Photonic representation and cells

- Keep ordinary Boolean vectors in source RTL. Expand bits into photonic rails
  during Yosys technology mapping.
- Encode each 32-bit word on paired true/false waveguides carrying 32 WDM
  channels: `01` is zero, `10` is one, `00` is invalid, and `11` is a fault.
- Use a nominal 100 GHz grid from 191.4 through 194.5 THz for data, 195.0 THz
  for control, 195.2 THz for clock, and 195.4 THz for reset. Allow per-ring
  thermal calibration.
- Characterize WDM mux/demux, ring add/drop, splitter, crossing, trim delay,
  TFLN chi2 LUT3, mux, parametric 2R regenerator, active-cavity time-bin state,
  butt coupler, and static PCM cells. Store logical models in Verilog and timing, loss,
  wavelength, recovery, tuning, and GDS metadata in JSON.
- Map combinational logic through Yosys/ABC LUT3 synthesis and insert explicit
  splitters and regenerators for fanout and loss.
- Implement the register file as a 32 by 32, two-read/one-write active-cavity
  time-bin state matrix with constant optical zero for `x0`.
- Use a parallel optical Kogge-Stone add/subtract network, five-level WDM
  barrel shifter, direct bitwise lanes, and subtraction-derived comparisons.
- Use PCM only for write-rare configuration/control constants, never registers
  or caches.
- Reject any CPU netlist containing photodetectors, ADCs, DACs, data-driven
  electrical modulators, or electrical control gates.

## Physical design

- Use a low-loss SiN interposer, TFLN nonlinear logic/state chiplets, and InP
  pump/gain chiplets partitioned into IF/I-cache, ID/register-file/CSR, EX,
  MEM/D-cache, and WB/retirement regions.
- Connect chiplets with butt-coupled spot-size converters and route clock,
  operands, forwarding, branch recovery, and writeback on the interposer.
- Distribute an external 100 GHz optical pulse clock through a balanced, trimmed SiN
  tree with ingress regeneration.
- Use Yosys 0.33, Icarus 12.0, Verilator 5.020, and pinned GDSFactory/KLayout
  environments with vendor PDK cells and verification decks.
- Generate separate GDSII files for the interposer and five chiplets plus an
  assembly manifest defining coordinates, optical ports, wavelengths,
  coupling tolerances, and calibration channels.
- Do not release full-chip GDS unless every extracted latch-to-latch path,
  including coupling, setup, skew, jitter, and PVT margin, closes below 10 ps.

## Verification and acceptance

- Preserve the Fibonacci and hazard regressions using handshake memory models.
- Add directed coverage for every RV32I/Zicsr instruction, forwarding path,
  branch result, trap, CSR behavior, cache operation, backpressure condition,
  and memory error.
- Add a formal/simulation-only RVFI interface and compare retirement traces
  against Spike.
- Run the official RV32I architectural tests and custom M-mode/cache tests.
- Use Yosys equivalence checking between logical cells and the zero-delay
  mapped photonic netlist.
- Assert legal dual-rail encoding, one-hot control, immutable `x0`, single
  store issuance, valid cache hits, and no retirement by killed instructions.
- Require deterministic reset for every state and memory macro; reject X/Z
  constants, tri-state, undriven or multiply driven nets, and post-reset X/Z
  values at mapped cell boundaries.
- Run extracted timing, loss, extinction, crosstalk, coupling-tolerance,
  thermal-detuning, and Monte Carlo process simulations.
- Require clean DRC/connectivity reports for every die and characterized
  optical power at every receiver before PIC-ready release.

## External prerequisites and boundaries

- TFLN nonlinear/state-cell and InP gain PDK access plus a SiN/PCM integration
  process are required for final PIC signoff. Without vendor models and decks,
  generated layouts are preliminary rather than tapeout-ready.
- External ROM and RAM use the optical handshake protocol at the CPU clock and
  may backpressure indefinitely.
- Tapeout purchasing/submission, coherent multicore, DMA snooping, vector and
  hypervisor extensions, and production JTAG/DMI transport are outside the
  current implementation scope.

## Implementation status

- [x] Specification persisted before RTL changes.
- [x] Baseline regression recorded (`PASS: CPU regression complete`).
- [x] RV32GC/ILP32D execution, M/S/U privilege, PMP, Sv32, debug, and RVFI
  compile surface implemented.
- [x] Split L1 caches and handshakes implemented.
- [x] Logical photonic-cell mapping and mapped regression implemented.
- [x] Loss-aware mandatory 100 GHz complete-netlist research timing closes.
- [x] Physical manifest/preflight release gate implemented.
- [ ] Vendor-PDK splitter/regenerator placement and GDS generation complete.
- [ ] External ISA/OS/debug compliance and physical signoff complete.

The open functional regressions cover RV32GC integer, atomic, compressed, and
floating-point execution; M/S/U traps, delegation, interrupts, PMP, Sv32,
debug control; cache operation, memory backpressure, and access errors. Final
certification and physical signoff remain blocked by the external suites and
vendor assets listed above; the generated preflight report records every
missing physical release input.

Preliminary structural timing rejected the mandatory 100 GHz CPU clock for the
former SOA/ring backend. The replacement `P_CHI2_LUT3`/`P_TBIN_DFF` research
contract and explicit PC/PMP/M/FPU macros map the full netlist and close the
10 ps model; see
`docs/architecture_signoff.md`. Vendor characterization, clock power delivery,
extracted routing, and physical verification remain release blockers.

The target rates are requirements, not claimed measurements of the abstract
LUT3 and state macros. They are motivated by demonstrated near-instantaneous
chi2 nonlinear processing and published TFLN nonlinear functions with allowable
clock rates above 13 THz, but each synthesized macro still requires foundry
implementation and characterization: [All-optical computing towards 100GHz clock rates](https://www.nature.com/articles/s41377-026-02314-5)
