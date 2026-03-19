# RV32I Pipelined Processor

> 5-Stage Pipeline · Full Data Forwarding · Hazard Detection · SystemVerilog RTL

---

## Overview

A complete, synthesizable RV32I implementation in SystemVerilog featuring a classic 5-stage pipeline: **IF → ID → EX → MEM → WB**. All 37 base integer instructions of the RISC-V RV32I ISA are supported, with full data forwarding to minimize stalls and correct handling of all hazard classes.

An interactive browser-based visual simulator is included — open `rv32i_simulator.html` in any modern browser to step through programs cycle-by-cycle and watch forwarding paths, stalls, and flushes in real time.

---

## Features

- All 37 RV32I base integer instructions (R, I, S, B, U, J types)
- 5-stage pipeline: IF → ID → EX → MEM → WB
- Full data forwarding (EX→EX and MEM→EX paths) via dedicated Forwarding Unit
- Load-use hazard detection with automatic 1-cycle stall insertion
- Branch resolution in EX stage with 2-cycle flush on taken branches
- Synchronous register file with read-after-write forwarding
- Byte-granular data memory — LB/LH/LBU/LHU with sign extension; SB/SH/SW
- Self-checking testbench with disassembler and per-cycle pipeline trace
- Interactive visual simulator with live forwarding indicators, register file, and performance stats

---

## File Structure

```
rv32i/
├── rtl/
│   ├── rv32i_pipeline.sv    # Top-level integration
│   ├── if_stage.sv           # IF: PC register, instruction fetch, branch redirect
│   ├── id_stage.sv           # ID: decoder, register file, immediate gen, ID/EX register
│   ├── ex_stage.sv           # EX: ALU, branch unit, forwarding unit, hazard detect, EX/MEM register
│   └── mem_wb_stage.sv       # MEM + WB stages and all pipeline registers
├── sim/
│   └── tb_rv32i.sv           # Testbench — Fibonacci self-check + pipeline trace
└── rv32i_simulator.html      # Interactive visual simulator (no server required)
```

---

## Architecture

### Pipeline Stages

| Stage | Module | Key Responsibilities |
|---|---|---|
| **IF** – Instruction Fetch | `if_stage.sv` | PC register, branch redirect, IMEM read |
| **ID** – Instruction Decode | `id_stage.sv` | Decoder, register file, immediate gen, ID/EX register |
| **EX** – Execute | `ex_stage.sv` | ALU, branch unit, forwarding unit, hazard detect, EX/MEM register |
| **MEM** – Memory Access | `mem_wb_stage.sv` | DMEM read/write, byte enables, sign extension, MEM/WB register |
| **WB** – Writeback | `mem_wb_stage.sv` | Mux between ALU result and load data; write to register file |

### Hazard Handling

**Data hazards** — The Forwarding Unit in EX resolves RAW hazards without stalls in the common case. It forwards from the EX/MEM register (one cycle old) and MEM/WB register (two cycles old) back to the ALU inputs.

**Load-use hazards** — When a load is followed immediately by a dependent instruction, the Hazard Detection Unit inserts one stall cycle: freezes IF and ID, flushes EX with a bubble.

**Control hazards** — Branches are resolved at the end of EX. On a taken branch, the two instructions already in IF and ID are flushed (2-cycle penalty). Not-taken branches incur no penalty.

---

## ISA Coverage

| Type | Instructions |
|---|---|
| R-type ALU | `ADD` `SUB` `SLL` `SLT` `SLTU` `XOR` `SRL` `SRA` `OR` `AND` |
| I-type ALU | `ADDI` `SLLI` `SLTI` `SLTIU` `XORI` `SRLI` `SRAI` `ORI` `ANDI` |
| Load | `LW` `LH` `LB` `LHU` `LBU` |
| Store | `SW` `SH` `SB` |
| Branch | `BEQ` `BNE` `BLT` `BGE` `BLTU` `BGEU` |
| Jump | `JAL` `JALR` |
| Upper Immediate | `LUI` `AUIPC` |

---

## Simulation

### Prerequisites

- Icarus Verilog ≥ 11, or any IEEE 1800-2012 SystemVerilog simulator (VCS, Questa, Xcelium)
- GTKWave (optional, for waveform viewing)

### Running the Testbench

```bash
# Compile and simulate
iverilog -g2012 -o rv32i_tb \
  rv32i/rtl/*.sv rv32i/sim/tb_rv32i.sv

vvp rv32i_tb

# View waveforms
gtkwave rv32i_wave.vcd
```

### Expected Output

```
=======================================================
 RV32I 5-Stage Pipelined Processor Simulation
=======================================================
 Program: Fibonacci F(10) = 55
=======================================================
 Cycle |    PC    | Instruction              | Stall | Flush | DMEM[0]
-------+----------+--------------------------+-------+-------+--------
     1 | 00000000 | addi x1,x0,0             |       |       | 0x00000000
     2 | 00000004 | addi x2,x0,1             |       |       | 0x00000000
     ...
    57 | 00000020 | sw   x2,0(x0)            |       |       | 0x00000037
=======================================================
 PASS: Fibonacci F(10) = 55 CORRECT!
=======================================================
```

---

## Visual Simulator

Open `rv32i_simulator.html` in any modern browser — no server or build step required.

### Controls

| Control | Description |
|---|---|
| Program selector | Choose from 5 built-in programs |
| Run / Pause | Executes continuously at configured speed |
| Step | Advances one clock cycle at a time |
| Reset | Restarts the selected program |
| Speed slider | 50 ms – 1000 ms per cycle |

### Display Panels

- **Pipeline diagram** — colour-coded stage blocks showing the instruction in each stage; `STALL` and `FLUSH` tags appear when active
- **Instruction memory** — live listing colour-coded by pipeline stage position
- **Register file** — all 32 registers with live values; recently written registers flash on writeback
- **Performance stats** — cycle count, instructions retired, CPI, IPC, stall %, flush %, efficiency
- **Data memory** — live 16-word view with flash animation on writes
- **Execution log** — per-cycle history of PC, instruction, and hazard events
- **Forwarding indicators** — active forwarding paths labelled with source register (e.g. `EX→EX rs1=x2`)

---

## Built-in Test Programs

| Program | What It Tests | Expected Result |
|---|---|---|
| Fibonacci F(10) | Loop control, back-to-back ALU ops, forwarding | `dmem[0] = 55` |
| Array Sum 1..10 | Accumulator loop, branch, store | `dmem[0] = 55` |
| Load-Use Hazard | Explicit load → dependent instruction (1 stall) | `dmem[4] = 85` |
| Branch Test | Branch taken flush, `max(7, 12)` | `dmem[0] = 12` |
| ALU All-Ops | All 10 ALU operations in sequence | `x3`–`x10` set |

---

## Performance

| Scenario | CPI |
|---|---|
| No hazards (ideal) | 1.0 |
| Every instruction is a load-use hazard | 2.0 |
| Every branch taken | 3.0 |
| Fibonacci F(10) (typical) | ~1.3 |

Forwarding eliminates stalls for all RAW hazards except load-use. Branches pay 2 cycles only when taken.

---

## Extending the Design

**M Extension (Multiply/Divide)** — Add `funct7=0x01` decoding in `id_stage.sv`, implement a multi-cycle multiplier, and stall EX via the hazard unit until the result is ready.

**Branch Prediction** — Replace the 2-cycle flush with a predictor (static not-taken, BTB, or gshare). Mispredictions flush and redirect via the same `branch_taken` path already present.

**Cache** — Replace the combinational IMEM/DMEM with a stalling cache interface and propagate cache stalls through the hazard unit to freeze all upstream stages.

---

## Implementation Notes

- All pipeline registers are positive-edge clocked with active-low synchronous reset
- The register file forwards on simultaneous read/write — WB takes priority over the stored value in the same cycle
- Branch target computation uses forwarded rs1/rs2 values in EX so branches on just-computed results work without extra stalls
- `JALR` clears bit 0 of the computed target per the RISC-V spec
- `LUI` passes 0 as ALU input A; `AUIPC` passes the current PC — both add the upper immediate through the same ADD path
- All modules are synthesisable; no `initial` blocks or non-synthesisable constructs outside the testbench

---

## License

MIT — free to use, modify, and distribute with attribution.
