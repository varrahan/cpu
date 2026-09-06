# Hybrid RV32GC CPU

This repository implements a four-wide RV32GC/ILP32D CPU with electronic
execution and storage and a shared wavelength-division-multiplexed transport
model. The execution cluster contains eight ALUs, two FPUs, two multiply/divide
units, and two LSUs. It has 256 integer and 256 FP physical registers, M/S/U
privilege, PMP, Sv32, interrupts, caches, and JTAG debug.

The hybrid core is the sole implementation. The WDM fabric models independent
channels, serialization, credits, and backpressure. It does not instantiate an
optical PHY, and neither an electronic clock frequency nor optical line rate
has been characterized. See [the architecture and validation](docs/hybrid_cpu.md).

## Run

```sh
make run                  # build and run CPU regression and parallelism tests
make check                # CPU, serialized fabric, shared units, formal, lint, JTAG
make architecture-cert    # additionally run ACT4, Sail, SoftFloat, OpenOCD, OS boot
make hybrid-synth         # electronic elaboration and Yosys structural checks
make hybrid-budget        # conditional WDM bandwidth and wavelength allocation
make os-check             # PraxisOS supervisor/user boot with Sv32
make openocd-debug-check   # external halt, register access, and resume
make formal               # fabric/allocator, PMP, cache/MMU/arbiter control proofs
make jtag-cdc-check        # structural checks for the JTAG transport crossings
```

`make` and the generic build/test targets select the hybrid CPU. Existing
`make hybrid-check`, `make hybrid-serial-check`, and `make hybrid-cert` commands
remain available. `TRACE=1` enables optional simulation waveform instrumentation.
Synthesis runs sequentially with a configurable 10 GiB process limit and cached
checkpoints so interrupted runs can resume.

The regression checks instruction, privilege, memory, debug, and parallel
execution behavior. The ACT4 hybrid profile uses the documented counter timing
adaptation; [the validation record](docs/hybrid_cpu.md#expanded-execution-cluster-validation)
separates its results from physical qualification. Tool and dependency revisions
are pinned in `tools.lock.json`.
