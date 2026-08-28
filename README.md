# Photonic RV32GC CPU

This repository contains a 32-bit RISC-V `RV32GC`/`ILP32D` CPU implementing
`IMAFD_Zicsr_Zifencei_C`, M/S/U privilege, interrupts/delegation, PMP, Sv32,
split 256-byte L1 caches, an abstract debug boundary, and ready/valid external
memory. A Yosys backend maps logic and state to photonic-cell contracts; the
source RTL remains the behavioral reference.

The open flow is functionally runnable, but it is not tapeout-ready. Vendor
TFLN/SiN/InP/PCM cells, extracted timing and optical-loss data,
KLayout verification decks, and final chiplet placement are required before
the release gate can pass. See [the implementation plan](docs/photonic_cpu_plan.md).

## Run

```sh
make run                 # RTL regression (run `make compile` first)
make stress-image        # build/audit the compiler-produced RV32GC workload
make architecture-check  # extended ISA/CSR tests, formal control, RVFI build
make photonic-cells      # logical photonic primitive checks
make photonic-check      # regress the mapped chi2/time-bin cell netlist
make known-state-check   # reject mapped X/Z, floating, or multiply driven nets
make timing-check        # require the 100 GHz research timing contract
make timing-signoff      # additionally require vendor characterization
make formal              # branch and hazard proofs
make formal-compile      # compile the optional RVFI interface
make physical-preflight  # emit build/physical/preflight.json
make check               # all of the above
make release-check       # require timing and physical tapeout signoff
```

The external instruction and data ports each use a one-outstanding-request
ready/valid protocol. The D-cache is write-through/no-write-allocate; both
caches fill four 32-bit beats per 16-byte line. At the physical boundary each
32-bit value is represented by true/false optical rails on the 32-channel WDM
plan in `photonic/wavelengths.json`.

The end-to-end regression compiles `sim/programs/rv32gc_stress.c` and its ISA
sweep with Clang/LLVM. It executes sorting, CRC32, matrix multiplication, GCD,
all RV32M and RV32A operations, all six CSR forms, and the RV32F/RV32D
arithmetic/compare/convert families through the real caches. The image gate
currently confirms 117 required mnemonics and 160 emitted compressed
instructions before the testbench checks its integer, atomic, CSR, and
floating-point signatures.

The optimized map uses 16,253 photonic LUT3s, 3,382 soft state cells, and six
parameterized photonic memory macros. Register files and cache tag/data banks
are inferred as memory IP instead of LUT read muxes; `physical/netlist_contract.py`
enforces the memory shapes, single-driver connectivity, and a 17,000-LUT
regression ceiling.

The no-unknown contract begins after `rst_n` is held low through a rising clock
edge and requires every external input to be driven to zero or one. All state,
including memory macros and validity-gated payloads, resets deterministically.
`make known-state-check` rejects X/Z constants, undriven or multiply driven
mapped nets, and any X/Z observed on mapped leaf-cell signals or CPU outputs
after reset. The core contains no tri-state buses.

`physical/preflight.py --require-release` fails until real GDS cells, six
layout files, coupling tolerances, and a clean extracted `physical/signoff.json`
are present. This prevents research target budgets from being presented as
PIC signoff.

Current clock results are recorded in
[the architecture/signoff report](docs/architecture_signoff.md). The complete
mapped research backend closes the mandatory 100 GHz contract with 0.800 ps
data slack and 1.005 ps predicate-reset slack; its estimated model Fmax is
110.39 GHz. The exploratory 120 GHz point fails. This is an architecture-model
result, not tapeout signoff: `make timing-signoff` and `make release-check`
remain blocked until a vendor characterizes the target cells and extracted
layout satisfies the same limits.
