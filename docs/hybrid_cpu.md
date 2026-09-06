# Four-wide hybrid RV32GC CPU

`rtl/top/hybrid_top.sv` preserves the RV32GC/ILP32D architectural interface:
32 integer and 32 FP architectural registers, M/S/U privilege, PMP, Sv32,
interrupts, debug, and the existing one-outstanding instruction/data ports.
Arithmetic, scheduling, and storage are electronic. Photonics is the shared
transport boundary. This is the sole CPU implementation; clock frequency and
optical line rate remain uncharacterized.

## Execution and storage

- Four decoders, eight integer ALUs, two M units, two FPnew units, and two LSUs.
  Issue and retirement remain four-wide. Each available operator selects a
  distinct ready instruction from its class; reservations are not bound to an
  issue lane. Eight ALUs can drain a ready backlog in one cycle, while sustained
  throughput remains limited by the four-wide frontend and register-bank ports.
- 256 integer and 256 FP physical registers, each class split into eight
  32-row banks with two read ports and one write port per bank. Integer banks
  store 32-bit values; FP banks store 64-bit values.
- 128 ROB entries, at most 64 waiting issue entries and 32 memory entries.
  The ROB stores reservation payloads; four age-ordered selectors choose ready
  instructions. Same-group rename observes earlier lanes' mappings.
- Four ordered retirement lanes. A result becomes ready after its bank write
  acknowledgement returns. Superseded physical mappings are freed at retirement;
  recovery restores the committed maps. FP flags become architectural at commit.
- A 128-byte fetch queue receives 16-byte cache lines. Four decompression/decode
  lanes handle mixed 16/32-bit instructions and cross-line/page boundaries.
  Permission faults in unused following halfwords do not trap earlier instructions.

Each LSU has independent address generation, Sv32 translation/PMP checks,
load/store formatting, and completion storage. The two oldest unfinished plain
loads may execute concurrently, including before the ROB head. Stores and atomics
launch only at the head. Translation must prove a speculative load cacheable
before it accesses data; MMIO waits at the head. Loads cannot pass an unfinished
store or atomic.

Electronic register and cache storage uses `rtl/memory/async_memory.v`; integer
and FP execution use `muldiv_unit` and `fpu_wrapper`.

The shared 256-byte data cache has two physical tag read ports and four 32-bit
data read ports, supporting two simultaneous 64-bit read hits. Its write port,
LR/SC reservation, miss machinery, and external port remain shared. The second
read port serves hits only while the cache is idle; misses serialize through
one held owner. A fault cancels younger loads, drains accepted cache/PTW requests,
and suppresses pending MMIO before recovery.
Branches execute without prediction and restart fetch at retirement. These
choices limit mixed-workload throughput despite four-wide independent issue.

Privilege changes, instruction fences, TLB flushes, traps, and debug entry wait
for accepted fetch and LSU transactions to drain. Internal packet epochs reject old
work after recovery; credit tokens also carry epochs. External requests retain
their existing ready/valid protocol. No external interface gains extra
outstanding requests.

## Shared transport

There are 52 independently backpressured producer channels on one logical
fabric. A producer owns its channel; destination collisions are handled by
finite bank ports and endpoint queues.

| Channels | Producer and traffic |
| --- | --- |
| 0–3 | Issue lanes: tagged commands and up to three register read requests |
| 4–35 | Two response lanes per PRF bank: operands and writeback acknowledgements |
| 36–43 | Eight integer ALU results |
| 44–45 | Two multiply/divide results |
| 46–47 | Two FP results |
| 48–49 | Two LSU results |
| 50–51 | Instruction line requests and responses |

The uniform forward frame is 307 bits, including epoch, ROB slot, destination,
kind, instruction, PC, and three 64-bit payload fields. Credit tokens are 33 bits
(epoch plus grant). Each channel has eight credits. `FABRIC_BITS_PER_CYCLE`,
`FABRIC_FLIGHT_CYCLES`, and `FABRIC_CREDIT_CYCLES` control serialization and
latency; defaults model one full frame per cycle and one-cycle flight/credit
delay. These are simulation parameters, not a characterized clock or line rate.

`physical/hybrid_budget.py` derives forward frame width from RTL and compares
one wavelength per producer with groups of 2, 4, and 8 wavelengths. It includes
credit bandwidth, queue round-trip limits, and optional receiver capacity.
For bank-balanced four-wide integer execution, the modeled traffic is 22
forward frames per cycle: **6,754 forward bits plus 726 credit bits**, compared
with a 512-bit useful-payload lower bound.

| Wavelengths per forward port | Forward + credit wavelengths | Minimum 32-channel waveguides |
| --- | --- | --- |
| 1 | 104 | 4 |
| 2 | 156 | 5 |
| 4 | 260 | 9 |
| 8 | 468 | 15 |

A single waveguide cannot carry this static channel allocation on the current
32-wavelength grid. The comparison reports that failure explicitly. Sharing a
wavelength among simultaneous producers would require arbitration and reduce
the assumed parallel bandwidth.

## Run and qualify

```sh
make hybrid-check          # CPU regression, parallel workload, fabric, budget, lint
make hybrid-serial-check   # full CPU regression with 64 bits/channel/cycle
make hybrid-formal         # endpoint safety and allocator equivalence proofs
make hybrid-cert           # hybrid checks plus ACT4, Sail, SoftFloat, Sv32 OS, OpenOCD
make hybrid-synth          # pinned sv2v conversion and Yosys electronic elaboration
make run
python3 physical/hybrid_budget.py --output build/hybrid/bandwidth.json
```

Clang++ 18 and C++20 compile the hybrid Verilator model. `hybrid-synth` downloads
sv2v 0.0.13 into `build/tools` when needed and verifies the archive checksum in
`tools.lock.json`. All CPU simulator targets build this implementation.
Yosys runs sequentially with a 10 GiB address-space limit
(`HYBRID_SYNTH_MEMORY_MB=10240`) and core dumps disabled. Completed parsing and
lowering stages are saved atomically in `build/hybrid/top.il`, `mux.il`,
`core.il`, and `optimized.il`, so interrupted runs can resume. Parsing, mux
conversion, storage lowering, optimization, and validation run in separate
processes to release temporary memory between stages. Optimization removes
unused internal names and merges duplicated logic before structural checking.
Validation uses short internal names to limit checker memory; module ports
retain their original names.
The synthesized ROB retains one row module
instantiated 128 times; expanding every row in one module exhausted this WSL
workspace's memory. Simulation uses the same row-update source in a loop.
`make formal` also checks shared PMP, data-cache, MMU, and arbiter control
properties. The cache proof uses abstract memory data. `make jtag-cdc-check`
checks the shared debug transport; it does not qualify whole-CPU CDC or timing.
Waveform instrumentation is optional: build with `TRACE=1` and run the directed
bench with `+trace` to produce a VCD. RVFI logging does not require waveform
instrumentation.

The hybrid ACT4 profile uses a separate copy of `Sm_mcsr_cntr-00`: its original
300-instruction wait loop assumes fewer than 1,000 CPU cycles. The port allows
100,000 cycles and retains both the low-word bound and high-word wrap-to-zero
checks. `sim/act4/hybrid_counter.py` verifies the exact source being changed;
ACT4 regenerates its Sail signature. The original source and ELF stay intact.
Results using this port are hybrid-profile results, not an unmodified ACT4 run.
The hybrid runner permits 30 million cycles per test (`ACT4_TIMEOUT`), including
the supervisor-interrupt test's long idle loops; this changes only the simulator
timeout.

The parallel benchmark requires at least eight consecutive cycles each of
four-wide issue and retirement, correct register results, and overlapping
memory/operand/result traffic. Measured full-frame runs achieve 11 issue cycles,
12 retire cycles, and 108 overlap cycles. The expanded core completes the existing
compiler stress workload in 11,551 cycles (previous hybrid: 11,919).
With 64-bit serialization it takes 26,319 cycles (previous hybrid: 26,991).
No general speedup is claimed.

`+operators_only`, included in `hybrid-check` and `hybrid-serial-check`, temporarily
backpressures ALU producers to accumulate a ready backlog, then checks eight
simultaneous ALU results and all architectural values. A mixed instruction stream
checks concurrent multiply/divide, FP, and LSU activity and simultaneous load
completions. Fault cases cover draining a younger cache miss and canceling a
younger MMIO load without an external device access.

Endpoint simulation checks ordering, serialization, independent backpressure,
credit recovery, reset, and flush. Bounded formal checks cover credit
conservation, capacity, reset/flush behavior, and stalled-output stability.
An exhaustive combinational proof checks that bank-local free-register encoders
preserve the rotating-bank, lowest-free-row allocation policy for every free map.
CPU assertions check map ownership, unique destinations, x0, queue bounds,
and ROB occupancy. Four-lane RVFI emits the existing 19-field trace format in
retirement order for the Sail comparator.

The table below records qualification of the previous 4-ALU/1-M/1-FP/1-LSU
implementation using the pinned tools in `tools.lock.json`; these results are
historical and do not by themselves qualify the expanded execution cluster.
Validation of the expanded cluster is recorded separately below.

| Check | Result |
| --- | --- |
| ACT4 RV32GC hybrid profile, including supervisor interrupts | 660/660 pass |
| Directed CPU regression, full-frame and serialized transport | Pass |
| Sustained four-wide issue/retirement and concurrent traffic | Pass |
| Sail/RVFI integer, atomic, FP, and interrupt comparison | 56,988 records match |
| SoftFloat arithmetic comparison | 6,111 cases pass |
| Endpoint simulation and 24-step bounded safety proof | Pass |
| Register allocator equivalence across all 256-bit free maps and eight bank starts | Pass |
| Electronic elaboration and Yosys structural checks | Pass; no blackboxes or latches; peak 7.6 GiB under the 8 GiB limit |
| Repeat synthesis with unchanged sources | Pass; all four checkpoints reused |
| External OpenOCD halt, register access, and resume | Pass |
| Halt/resume exactly at MRET and SRET retirement | Pass, full-frame and serialized transport |
| Machine-to-Sv32 boot | Pass, 31,327 cycles |
| PraxisOS Sv32 supervisor/user boot and process exit | Pass, 9,466,102 cycles |

## Expanded execution cluster validation

- Directed RV32GC/privilege/debug regression passes with full-frame and
  64-bit serialized transport.
- Eight ALU results in one cycle. Full-frame tests observe both M units computing
  for 46 cycles, both FP units for 65 cycles, both LSU requests active for 60
  cycles, and 32 simultaneous load completions. Serialized tests observe
  44/65/61 cycles respectively and the same 32 paired load completions.
- Both transport settings pass fault recovery with accepted cache misses and
  pending younger MMIO loads. Single-step retires exactly once, including when
  the external data bus is blocked. Endpoint simulation and strict lint pass.
- Endpoint bounded proof and allocator equivalence pass.
- Sail/RVFI comparisons match 56,960 integer, atomic, and FP retirement records;
  machine-to-Sv32 boot passes in 31,326 cycles.
- PraxisOS Sv32 supervisor/user boot and process exit passes in 9,444,335 cycles.
- Four-wide issue/retirement benchmark and the updated 52-channel budget pass.
- ACT4 RV32GC hybrid profile: 660/660 pass, including supervisor interrupts.
- Electronic elaboration and Yosys structural checks pass with no blackboxes or
  latches. The netlist contains eight ALUs, two M units, two FP units, and two LSU
  datapaths. Peak memory is 8.6 GiB under the 10 GiB process limit; all four
  checkpoints were reused on the final validation run.

## Physical status

`wdm_fabric.sv` is a synchronous, synthesizable transport contract. It does not
instantiate modulators, receivers, optical routing, or an asynchronous PHY.
`photonic/hybrid_fabric.json` deliberately leaves line rate, conversion delay,
propagation, receiver capacity, optical power/loss, thermal trim, and electronic
Fmax uncharacterized. The budget report always identifies physical signoff as
false; it reports conditional transport ceilings rather than inventing a CPU
frequency. Vendor PHY integration, CDC/reset implementation, electronic timing,
and extracted optical layout/power qualification remain release blockers.
