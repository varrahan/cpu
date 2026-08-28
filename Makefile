CC = iverilog
SIM = vvp
OUT = build/top_sim.vvp
WAVE = build/top_wave.vcd
VERILATOR_DIR = build/verilator/top
VERILATOR_BIN = $(VERILATOR_DIR)/Vtb_top
PHOTONIC_DIR = build/photonic
PHOTONIC_NETLIST = $(PHOTONIC_DIR)/top_mapped.v
ARCH_DIR = build/architecture
PROGRAM_DIR = build/programs
STRESS_SRC = sim/programs/rv32gc_stress.c sim/programs/rv32gc_sweep.S
STRESS_LINK = sim/programs/rv32gc_stress.ld
STRESS_COVERAGE = sim/check_stress_coverage.py
STRESS_ELF = $(PROGRAM_DIR)/rv32gc_stress.elf
STRESS_BIN = $(PROGRAM_DIR)/rv32gc_stress.bin
STRESS_HEX = $(PROGRAM_DIR)/rv32gc_stress.hex

.PHONY: all compile run clean photonic-map photonic-check photonic-cells \
	architecture-units architecture-check physical-preflight physical-release \
	timing-check timing-explore timing-signoff formal formal-compile check \
	release-check extended-units fpu-check pmp-check sv32-check debug-check \
	photonic-macros known-state-check stress-image

FETCH_SRC = rtl/fetch/rvc_decompressor.v \
            rtl/fetch/fetch_stage.v

DECODE_SRC = rtl/decode/decoder.v \
             rtl/decode/regfile.v \
             rtl/decode/fp_regfile.v \
             rtl/decode/csr_file.v \
             rtl/decode/decode_execute_register.v

EXEC_SRC = rtl/execute/alu.v \
           rtl/execute/branch_unit.v \
           rtl/execute/forwarding_unit.v \
           rtl/execute/hazard_unit.v \
           rtl/execute/muldiv_unit.v \
           rtl/execute/fpu_wrapper.sv \
           rtl/execute/execute_memory_register.v

MEM_SRC = rtl/memory/memory_stage.v \
          rtl/memory/pmp_checker.v \
          rtl/memory/sv32_mmu.v \
          rtl/memory/memory_arbiter4.v \
          rtl/memory/icache.v \
          rtl/memory/dcache.v \
          rtl/memory/memory_writeback_register.v

WB_SRC = rtl/writeback/writeback_stage.v

DEBUG_SRC = rtl/debug/debug_control.v

TOP_SRC = rtl/top/top.v

RTL_SRC = rtl/photonic/photonic_memories.v \
	$(FETCH_SRC) $(DECODE_SRC) $(EXEC_SRC) $(MEM_SRC) $(WB_SRC) \
	$(DEBUG_SRC) $(TOP_SRC)

TB_SRC = sim/tb_top.v

COMMON_CELLS_SRC = third_party/common_cells/src/cf_math_pkg.sv \
	third_party/common_cells/src/lzc.sv \
	third_party/common_cells/src/rr_arb_tree.sv

FPNEW_SRC = third_party/cvfpu/src/fpnew_pkg.sv \
	third_party/cvfpu/vendor/opene906/E906_RTL_FACTORY/gen_rtl/clk/rtl/gated_clk_cell.v \
	$(wildcard third_party/cvfpu/vendor/openc910/C910_RTL_FACTORY/gen_rtl/vfdsu/rtl/*.v) \
	third_party/cvfpu/src/fpnew_classifier.sv \
	third_party/cvfpu/src/fpnew_rounding.sv \
	third_party/cvfpu/src/fpnew_fma.sv \
	third_party/cvfpu/src/fpnew_fma_multi.sv \
	third_party/cvfpu/src/fpnew_noncomp.sv \
	third_party/cvfpu/src/fpnew_cast_multi.sv \
	third_party/cvfpu/src/fpnew_divsqrt_th_32.sv \
	third_party/cvfpu/src/fpnew_divsqrt_th_64_multi.sv \
	third_party/cvfpu/src/fpnew_divsqrt_multi.sv \
	third_party/cvfpu/src/fpnew_opgroup_fmt_slice.sv \
	third_party/cvfpu/src/fpnew_opgroup_multifmt_slice.sv \
	third_party/cvfpu/src/fpnew_opgroup_block.sv \
	third_party/cvfpu/src/fpnew_top.sv

VERILATOR_FLAGS = --binary --timing --trace \
	-Ithird_party/common_cells/include -Wno-fatal -Wno-TIMESCALEMOD \
	-Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-UNOPTFLAT -Wno-ASCRANGE \
	-Wno-UNSIGNED

all: compile run

photonic-map:
	mkdir -p $(PHOTONIC_DIR)
	yosys -q -s synth/photonic.ys

photonic-check: photonic-map photonic-macros
	python3 physical/netlist_contract.py

photonic-cells:
	mkdir -p $(PHOTONIC_DIR)
	iverilog -g2012 -s tb_photonic_cells -o $(PHOTONIC_DIR)/cells.vvp \
		rtl/photonic/photonic_cells.v sim/tb_photonic_cells.v
	vvp $(PHOTONIC_DIR)/cells.vvp

photonic-macros:
	mkdir -p $(PHOTONIC_DIR)
	iverilog -g2012 -s tb_photonic_macros -o $(PHOTONIC_DIR)/macros.vvp \
		rtl/photonic/photonic_memories.v \
		rtl/fetch/rvc_decompressor.v rtl/fetch/fetch_stage.v \
		rtl/memory/pmp_checker.v rtl/execute/muldiv_unit.v \
		sim/tb_photonic_macros.v
	vvp $(PHOTONIC_DIR)/macros.vvp

known-state-check: $(STRESS_HEX) photonic-map
	iverilog -g2012 -s tb_mapped_known -o $(PHOTONIC_DIR)/known_state.vvp \
		rtl/photonic/photonic_cells.v rtl/photonic/photonic_memories.v \
		sim/photonic_macro_known_models.v $(PHOTONIC_NETLIST) \
		sim/tb_mapped_known.v
	vvp $(PHOTONIC_DIR)/known_state.vvp
	python3 physical/check_vcd_known.py

architecture-units:
	mkdir -p $(ARCH_DIR)
	iverilog -g2012 -s tb_arch_units -o $(ARCH_DIR)/units.vvp \
		rtl/decode/decoder.v rtl/decode/csr_file.v sim/tb_arch_units.v
	vvp $(ARCH_DIR)/units.vvp

extended-units:
	mkdir -p $(ARCH_DIR)
	iverilog -g2012 -s tb_extended_units -o $(ARCH_DIR)/extended.vvp \
		rtl/fetch/rvc_decompressor.v rtl/execute/muldiv_unit.v \
		sim/tb_extended_units.v
	vvp $(ARCH_DIR)/extended.vvp

fpu-check:
	mkdir -p build/verilator/fpu
	verilator $(VERILATOR_FLAGS) --top-module tb_fpu \
		-Mdir build/verilator/fpu $(COMMON_CELLS_SRC) $(FPNEW_SRC) \
		rtl/execute/fpu_wrapper.sv sim/tb_fpu.sv
	build/verilator/fpu/Vtb_fpu

pmp-check:
	mkdir -p $(ARCH_DIR)
	iverilog -g2012 -s tb_pmp -o $(ARCH_DIR)/pmp.vvp \
		rtl/memory/pmp_checker.v sim/tb_pmp.v
	vvp $(ARCH_DIR)/pmp.vvp

sv32-check:
	mkdir -p $(ARCH_DIR)
	iverilog -g2012 -s tb_sv32 -o $(ARCH_DIR)/sv32.vvp \
		rtl/memory/sv32_mmu.v sim/tb_sv32.v
	vvp $(ARCH_DIR)/sv32.vvp

debug-check:
	mkdir -p $(ARCH_DIR)
	iverilog -g2012 -s tb_debug -o $(ARCH_DIR)/debug.vvp \
		rtl/debug/debug_control.v sim/tb_debug.v
	vvp $(ARCH_DIR)/debug.vvp

architecture-check: compile run architecture-units extended-units fpu-check \
	pmp-check sv32-check debug-check formal formal-compile

physical-preflight: photonic-map
	python3 physical/preflight.py

timing-check: photonic-map
	python3 physical/timing.py --frequencies-ghz 100 --require-model-pass

timing-explore: photonic-map
	python3 physical/timing.py --frequencies-ghz 100 120

timing-signoff: photonic-map
	python3 physical/timing.py --frequencies-ghz 100 --require-pass

physical-release: photonic-map
	python3 physical/preflight.py --require-release

formal:
	sby -f -d build/formal/control formal/control.sby

formal-compile:
	mkdir -p build/formal
	iverilog -g2012 -DSYNTHESIS -DRISCV_FORMAL -s top \
		-o build/formal/rvfi.vvp $(RTL_SRC)

check: architecture-check photonic-cells photonic-check known-state-check \
	physical-preflight timing-check

release-check: check timing-signoff physical-release

$(STRESS_HEX): $(STRESS_SRC) $(STRESS_LINK) $(STRESS_COVERAGE)
	mkdir -p $(PROGRAM_DIR)
	clang --target=riscv32-unknown-elf -march=rv32gc -mabi=ilp32d -Oz \
		-ffreestanding -fno-builtin -fno-stack-protector -fno-pic \
		-nostdlib -Wl,-T,$(STRESS_LINK),--no-relax -o $(STRESS_ELF) $(STRESS_SRC)
	llvm-objcopy -O binary --only-section=.text $(STRESS_ELF) $(STRESS_BIN)
	od -An -v -tx4 -w4 $(STRESS_BIN) > $(STRESS_HEX)
	printf '@00001fff\n00000013\n' >> $(STRESS_HEX)
	llvm-objdump -d -M no-aliases $(STRESS_ELF) > $(PROGRAM_DIR)/rv32gc_stress.dump
	python3 $(STRESS_COVERAGE) $(PROGRAM_DIR)/rv32gc_stress.dump

stress-image: $(STRESS_HEX)

compile: $(STRESS_HEX)
	@echo "Compiling RTL and Testbench..."
	mkdir -p $(VERILATOR_DIR)
	verilator $(VERILATOR_FLAGS) --top-module tb_top -Mdir $(VERILATOR_DIR) \
		$(COMMON_CELLS_SRC) $(FPNEW_SRC) $(RTL_SRC) $(TB_SRC)

run:
	@echo "Running Simulation..."
	$(VERILATOR_BIN)

clean:
	rm -f $(OUT) $(WAVE)

	@echo "Clean complete."
