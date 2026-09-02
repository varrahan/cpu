CC = iverilog
SIM = vvp
OUT = build/top_sim.vvp
WAVE = build/top_wave.vcd
VERILATOR_DIR = build/verilator/top
VERILATOR_BIN = $(VERILATOR_DIR)/Vtb_top
PHOTONIC_DIR = build/photonic
PHOTONIC_NETLIST = $(PHOTONIC_DIR)/top_mapped.v
PHYSICAL_NETLIST = build/physical/top_physical.json
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
	photonic-macros known-state-check stress-image architecture-cert \
	lint-check cdc-check jtag-debug-check rvfi-diff softfloat-check boot-check \
	photonic-physical equivalence-check dft-check toolchain-check reproduce-check

FETCH_SRC = rtl/fetch/rvc_decompressor.v \
            rtl/fetch/fetch_stage.v

DECODE_SRC = rtl/decode/decoder.v \
             rtl/decode/regfile.v \
             rtl/decode/fp_regfile.v \
             rtl/decode/csr_file.v

EXEC_SRC = rtl/execute/alu.v \
           rtl/execute/branch_unit.v \
           rtl/execute/forwarding_unit.v \
           rtl/execute/hazard_unit.v \
           rtl/execute/muldiv_unit.v \
           rtl/execute/fpu_wrapper.sv

MEM_SRC = rtl/memory/memory_stage.v \
          rtl/memory/pmp_checker.v \
          rtl/memory/sv32_mmu.v \
          rtl/memory/memory_arbiter4.v \
          rtl/memory/icache.v \
          rtl/memory/dcache.v

DEBUG_SRC = rtl/debug/debug_control.v \
	rtl/debug/riscv_debug_transport.sv

TOP_SRC = rtl/top/top.v

RTL_SRC = rtl/photonic/photonic_memories.v \
	$(FETCH_SRC) $(DECODE_SRC) $(EXEC_SRC) $(MEM_SRC) \
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
	third_party/cvfpu/src/fpnew_noncomp.sv \
	third_party/cvfpu/src/fpnew_cast_multi.sv \
	third_party/cvfpu/src/fpnew_divsqrt_th_64_multi.sv \
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

photonic-physical: photonic-map
	python3 physical/insert_support.py

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

physical-preflight: photonic-physical
	python3 physical/preflight.py

timing-check: photonic-physical
	python3 physical/timing.py --physical-netlist $(PHYSICAL_NETLIST) \
		--require-model-pass

timing-explore: photonic-physical
	python3 physical/timing.py --physical-netlist $(PHYSICAL_NETLIST) \
		--frequencies-ghz 100 120

timing-signoff: photonic-physical
	python3 physical/timing.py --physical-netlist $(PHYSICAL_NETLIST) \
		--require-pass

physical-release: photonic-physical
	python3 physical/preflight.py --require-release

formal:
	sby -f -d build/formal/control formal/control.sby
	sby -f -d build/formal/pmp formal/pmp.sby
	sby -f -d build/formal/safety formal/safety.sby
	sby -f -d build/formal/top formal/top.sby

formal-compile:
	mkdir -p build/formal
	iverilog -g2012 -DSYNTHESIS -DRISCV_FORMAL -s top \
		-o build/formal/rvfi.vvp $(RTL_SRC)

equivalence-check:
	mkdir -p build/equivalence
	yosys -q -s synth/equivalence.ys
	yosys-abc -c "cec -T 120 -p build/equivalence/gold.aig build/equivalence/gate.aig" \
		> build/equivalence/cec.log
	grep -q "Networks are equivalent" build/equivalence/cec.log
	@echo "PASS: RTL and LUT-mapped netlist are equivalent"

dft-check:
	python3 physical/check_dft.py

toolchain-check: act4-source softfloat-source
	python3 sim/check_toolchain.py

reproduce-check:
	$(MAKE) clean
	$(MAKE) toolchain-check architecture-cert

check: architecture-check photonic-cells photonic-check photonic-physical \
	equivalence-check known-state-check physical-preflight timing-check dft-check

release-check: architecture-cert timing-signoff physical-release

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
	rm -rf build
	@echo "Clean complete."

ACT4_DIR = build/act4
ACT4_SRC = $(ACT4_DIR)/source
ACT4_REV = 1cb285fe70ecc375422d2a72b7b5183a9f0ea771
ACT4_IMAGE = ghcr.io/riscv/act4-build:act4@sha256:6c1967e40bb17ef23b9a175529882128dd04d76990f13fafa7c9756bac761a77
ACT4_WORK = work/photonic
ACT4_CONFIG_DIR = $(ACT4_SRC)/config/photonic-rv32gc
ACT4_CONFIG = config/photonic-rv32gc/test_config.yaml
ACT4_EXTENSIONS = I,M,F,D,Zicsr,Zifencei,Zca,Zcf,Zcd,Zaamo,Zalrsc
ACT4_ELFS = $(ACT4_SRC)/$(ACT4_WORK)/photonic-rv32gc/elfs/rv32i
ACT4_HEX = $(ACT4_DIR)/hex-rv32gc
ACT4_JOBS ?= 8
RVFI_INST_LIMIT ?= 100000
ACT4_VERILATOR_DIR = build/verilator/act4
ACT4_BIN = $(ACT4_VERILATOR_DIR)/Vtb_act4
SOFTFLOAT_REV = a0c6494cdc11865811dec815d5c0049fba9d82a8
SOFTFLOAT_SRC = build/softfloat/source
SOFTFLOAT_BUILD = $(SOFTFLOAT_SRC)/build/Linux-x86_64-GCC
SOFTFLOAT_RISCV = $(SOFTFLOAT_BUILD)/.riscv-specialization
BOOT_ELF = $(PROGRAM_DIR)/architecture_boot.elf
BOOT_HEX = $(PROGRAM_DIR)/architecture_boot.hex
INTERRUPT_ELF = $(PROGRAM_DIR)/interrupt_diff.elf
INTERRUPT_HEX = $(PROGRAM_DIR)/interrupt_diff.hex
INTERRUPT_TOHOST = $(PROGRAM_DIR)/interrupt_diff.tohost

.PHONY: act4-source act4-config act4-elfs act4-compile act4-hex \
	act4-official softfloat-source softfloat-check boot-image boot-check \
	rvfi-diff interrupt-image lint-check cdc-check jtag-debug-check architecture-cert

act4-source:
	@if [ ! -d $(ACT4_SRC)/.git ]; then \
		mkdir -p $(ACT4_SRC); \
		git -C $(ACT4_SRC) init; \
		git -C $(ACT4_SRC) remote add origin https://github.com/riscv/riscv-arch-test.git; \
		git -C $(ACT4_SRC) fetch --depth 1 origin $(ACT4_REV); \
		git -C $(ACT4_SRC) checkout --detach FETCH_HEAD; \
	fi
	@test "$$(git -C $(ACT4_SRC) rev-parse HEAD)" = "$(ACT4_REV)"

act4-config: act4-source
	mkdir -p $(ACT4_CONFIG_DIR)
	cp sim/act4/test_config.yaml sim/act4/photonic-rv32gc.yaml $(ACT4_CONFIG_DIR)/
	ln -sfn ../sail/sail-rv32-max/link.ld $(ACT4_CONFIG_DIR)/link.ld
	ln -sfn ../sail/sail-rv32-max/rvmodel_macros.h $(ACT4_CONFIG_DIR)/rvmodel_macros.h
	ln -sfn ../sail/sail-rv32-max/sail.json $(ACT4_CONFIG_DIR)/sail.json

act4-elfs: act4-config
	docker run --rm -v $(abspath $(ACT4_SRC)):/act4 -w /act4 \
		$(ACT4_IMAGE) make CONFIG_FILES=$(ACT4_CONFIG) \
		WORKDIR=$(ACT4_WORK) EXTENSIONS=$(ACT4_EXTENSIONS) FAST=True -j8

act4-compile:
	mkdir -p $(ACT4_VERILATOR_DIR)
	verilator $(VERILATOR_FLAGS) -DRISCV_FORMAL --top-module tb_act4 \
		-Mdir $(ACT4_VERILATOR_DIR) $(COMMON_CELLS_SRC) $(FPNEW_SRC) \
		$(RTL_SRC) sim/tb_act4.sv

act4-hex: act4-elfs
	mkdir -p $(ACT4_HEX)
	docker run --rm -v $(abspath $(ACT4_SRC)):/act4:ro \
		-v $(abspath $(ACT4_HEX)):/hex $(ACT4_IMAGE) sh -c \
		'find /act4/$(ACT4_WORK)/photonic-rv32gc/elfs/rv32i -name "*.elf" | while read elf; do \
			ext=$$(basename "$$(dirname "$$elf")"); name=$$(basename "$$elf" .elf); \
			mkdir -p "/hex/$$ext"; \
		riscv64-unknown-elf-objcopy -O verilog --verilog-data-width=1 \
			"$$elf" "/hex/$$ext/$$name.hex"; \
		riscv64-unknown-elf-nm "$$elf" | grep " tohost$$" | cut -d" " -f1 \
			> "/hex/$$ext/$$name.tohost"; \
		sed -i "s/^@8/@0/" "/hex/$$ext/$$name.hex"; \
		done'

act4-official: act4-compile act4-hex
	@mkdir -p $(ACT4_DIR)/logs; \
	find $(ACT4_HEX) -name '*.hex' -print0 | sort -z | \
		xargs -0 -n1 -P$(ACT4_JOBS) sh -c ' \
			hex="$$1"; name=$${hex##*/}; name=$${name%.hex}; \
			tohost=$$(cat "$${hex%.hex}.tohost"); \
			log="$(ACT4_DIR)/logs/$${hex#$(ACT4_HEX)/}"; log=$${log%.hex}.log; \
			mkdir -p "$${log%/*}"; \
			if $(ACT4_BIN) +hex="$$hex" +test="$$name" +tohost="$$tohost" +reset_high +timeout=5000000 >"$$log" 2>&1; then \
				echo "PASS $$name"; \
			else \
				echo "FAIL $$name ($$log)"; exit 1; \
			fi' _ >$(ACT4_DIR)/official-results.log; \
	status=$$?; cat $(ACT4_DIR)/official-results.log; \
	total=$$(wc -l <$(ACT4_DIR)/official-results.log); \
	passed=$$(grep -c '^PASS ' $(ACT4_DIR)/official-results.log || true); \
	echo "ACT4 supported ISA: $$passed/$$total passed"; \
	exit $$status

softfloat-source:
	@if [ ! -d $(SOFTFLOAT_SRC)/.git ]; then \
		git clone --filter=blob:none https://github.com/ucb-bar/berkeley-softfloat-3.git $(SOFTFLOAT_SRC); \
		git -C $(SOFTFLOAT_SRC) checkout --detach $(SOFTFLOAT_REV); \
	fi
	@test "$$(git -C $(SOFTFLOAT_SRC) rev-parse HEAD)" = "$(SOFTFLOAT_REV)"

$(SOFTFLOAT_RISCV): softfloat-source
	$(MAKE) -C $(SOFTFLOAT_BUILD) clean
	$(MAKE) -C $(SOFTFLOAT_BUILD) SPECIALIZE_TYPE=RISCV -j8
	touch $@

softfloat-check: $(SOFTFLOAT_RISCV)
	mkdir -p build/verilator/softfloat
	verilator $(VERILATOR_FLAGS) --top-module tb_fpu_random \
		-Mdir build/verilator/softfloat $(COMMON_CELLS_SRC) $(FPNEW_SRC) \
		rtl/execute/fpu_wrapper.sv sim/tb_fpu_random.sv \
		$(abspath sim/softfloat_dpi.c) \
		-CFLAGS "-I$(abspath $(SOFTFLOAT_SRC)/source/include)" \
		-LDFLAGS "$(abspath $(SOFTFLOAT_BUILD)/softfloat.a)"
	build/verilator/softfloat/Vtb_fpu_random

boot-image: act4-source
	mkdir -p $(PROGRAM_DIR)
	docker run --rm -v $(abspath .):/cpu -w /cpu $(ACT4_IMAGE) sh -c \
		'riscv64-unknown-elf-gcc -march=rv32gc -mabi=ilp32d -mcmodel=medany \
			-nostdlib -nostartfiles -T sim/programs/architecture_boot.ld \
			-o $(BOOT_ELF) sim/programs/architecture_boot.S && \
		riscv64-unknown-elf-objcopy -O verilog --verilog-data-width=1 \
			$(BOOT_ELF) $(BOOT_HEX)'

boot-check: act4-compile boot-image
	$(ACT4_BIN) +hex=$(BOOT_HEX) +test=machine-to-sv32-boot +timeout=1000000

interrupt-image:
	mkdir -p $(PROGRAM_DIR)
	docker run --rm -v $(abspath .):/cpu -w /cpu $(ACT4_IMAGE) sh -c \
		'riscv64-unknown-elf-gcc -march=rv32gc -mabi=ilp32d -nostdlib \
			-nostartfiles -T sim/programs/interrupt_diff.ld -o $(INTERRUPT_ELF) \
			sim/programs/interrupt_diff.S && \
		riscv64-unknown-elf-objcopy -O verilog --verilog-data-width=1 \
			$(INTERRUPT_ELF) $(INTERRUPT_HEX) && \
		riscv64-unknown-elf-nm $(INTERRUPT_ELF) | grep " tohost$$" | cut -d" " -f1 \
			> $(INTERRUPT_TOHOST) && sed -i "s/^@8/@0/" $(INTERRUPT_HEX)'

rvfi-diff: act4-compile act4-hex interrupt-image
	@mkdir -p build/rvfi; set -e; \
	for case in I/I-add-00 Zaamo/Zaamo-amoadd.w-00 D/D-fmadd.d-00; do \
		stem=$${case%/*}-$${case#*/}; \
		$(ACT4_BIN) +hex=$(ACT4_HEX)/$$case.hex +test=rvfi-$$stem \
			+tohost=$$(cat $(ACT4_HEX)/$$case.tohost) +reset_high \
			+rvfi=build/rvfi/$$stem.dut.log +timeout=5000000; \
		docker run --rm -v $(abspath $(ACT4_SRC)):/act4 -w /act4 \
			$(ACT4_IMAGE) sail_riscv_sim \
			--config config/photonic-rv32gc/sail.json \
			--inst-limit $(RVFI_INST_LIMIT) \
			--trace-instr --trace-gpr --trace-fpr --trace-csr --trace-mem \
			--trace-exception --trace-interrupt \
			--trace-output work/photonic/$$stem.sail.log \
			work/photonic/photonic-rv32gc/elfs/rv32i/$$case.elf; \
		python3 sim/compare_rvfi.py build/rvfi/$$stem.dut.log \
			$(ACT4_SRC)/work/photonic/$$stem.sail.log; \
	done
	@set -e; rm -f build/rvfi/interrupt.sail.log; \
	$(ACT4_BIN) +hex=$(INTERRUPT_HEX) +test=rvfi-interrupt \
		+tohost=$$(cat $(INTERRUPT_TOHOST)) +reset_high \
		+rvfi=build/rvfi/interrupt.dut.log +timeout=100000; \
	docker run --rm -v $(abspath .):/cpu -w /cpu $(ACT4_IMAGE) sail_riscv_sim \
		--config build/act4/source/config/photonic-rv32gc/sail.json \
		--inst-limit $(RVFI_INST_LIMIT) \
		--trace-instr --trace-gpr --trace-fpr --trace-csr --trace-mem \
		--trace-exception --trace-interrupt \
		--trace-output build/rvfi/interrupt.sail.log $(INTERRUPT_ELF); \
	python3 sim/compare_rvfi.py build/rvfi/interrupt.dut.log \
		build/rvfi/interrupt.sail.log --allow-interrupt-latency \
		--require memory interrupts csr
	python3 sim/compare_rvfi.py build/rvfi/D-D-fmadd.d-00.dut.log \
		$(ACT4_SRC)/work/photonic/D-D-fmadd.d-00.sail.log \
		--require memory privilege traps fp csr

lint-check:
	verilator --lint-only --timing --top-module top_jtag \
		-Wall -Wno-fatal -Wno-TIMESCALEMOD \
		-Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-UNOPTFLAT -Wno-ASCRANGE \
		-Wno-UNSIGNED -Ithird_party/common_cells/include rtl/lint.vlt \
		$(COMMON_CELLS_SRC) $(FPNEW_SRC) $(RTL_SRC) rtl/top/top_jtag.sv

cdc-check:
	mkdir -p build/cdc
	yosys -q -s synth/cdc.ys
	python3 sim/check_cdc.py

jtag-debug-check:
	mkdir -p $(ARCH_DIR)
	iverilog -g2012 -s tb_jtag_debug -o $(ARCH_DIR)/jtag_debug.vvp \
		rtl/debug/riscv_debug_transport.sv sim/tb_jtag_debug.sv
	vvp $(ARCH_DIR)/jtag_debug.vvp

architecture-cert: check lint-check cdc-check jtag-debug-check \
	act4-official rvfi-diff softfloat-check boot-check
