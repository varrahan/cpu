.DEFAULT_GOAL := all
ARCH_DIR = build/architecture
PROGRAM_DIR = build/programs
STRESS_SRC = sim/programs/rv32gc_stress.c sim/programs/rv32gc_sweep.S
STRESS_LINK = sim/programs/rv32gc_stress.ld
STRESS_COVERAGE = sim/check_stress_coverage.py
STRESS_ELF = $(PROGRAM_DIR)/rv32gc_stress.elf
STRESS_BIN = $(PROGRAM_DIR)/rv32gc_stress.bin
STRESS_HEX = $(PROGRAM_DIR)/rv32gc_stress.hex

.PHONY: all compile run clean check architecture-check architecture-cert \
	architecture-units extended-units fpu-check pmp-check sv32-check debug-check \
	memory-check formal formal-compile lint-check jtag-cdc-check jtag-debug-check \
	stress-image toolchain-check reproduce-check

HYBRID_SRC = rtl/top/hybrid_pkg.sv \
	rtl/photonic/wdm_fabric.sv \
	rtl/memory/hybrid_icache.sv rtl/memory/hybrid_memory.sv \
	rtl/top/hybrid_top.sv
HYBRID_RTL = rtl/memory/async_memory.sv rtl/fetch/rvc_decompressor.sv \
	rtl/decode/decoder.sv rtl/decode/csr_file.sv \
	rtl/execute/alu.sv rtl/execute/muldiv_unit.sv rtl/execute/fpu_unit.sv \
	rtl/memory/memory_stage.sv rtl/memory/pmp_checker.sv rtl/memory/sv32_mmu.sv \
	rtl/memory/memory_arbiter4.sv rtl/memory/dcache.sv \
	rtl/debug/debug_control.sv rtl/debug/riscv_debug_transport.sv
RTL_SRC = $(HYBRID_SRC) $(HYBRID_RTL)
CORE ?= hybrid
ifneq ($(CORE),hybrid)
$(error Only the hybrid CPU is supported)
endif
HYBRID_VERILATOR_FLAGS = --assert -CFLAGS "-O1 -std=c++20" -MAKEFLAGS CXX=clang++ --output-split-cfuncs 500
CORE_DEFINES = -DRISCV_FORMAL
HYBRID_BUILD_DIR ?= build/verilator/hybrid
HYBRID_TRACE_FLAGS = $(if $(filter 1,$(TRACE)),--trace)
SV2V ?= build/tools/sv2v
HYBRID_SYNTH_MEMORY_MB ?= 10240
HYBRID_YOSYS = prlimit --as=$$(( $(HYBRID_SYNTH_MEMORY_MB) * 1024 * 1024 )) --core=0 -- yosys

.PHONY: hybrid-compile hybrid-run hybrid-lint
.PHONY: hybrid-fabric-check hybrid-budget
hybrid-fabric-check:
	mkdir -p build/verilator/wdm
	verilator --binary --timing --assert -Wno-fatal --top-module tb_wdm_fabric \
		-Mdir build/verilator/wdm rtl/top/hybrid_pkg.sv \
		rtl/photonic/wdm_fabric.sv sim/tb_wdm_fabric.sv
	build/verilator/wdm/Vtb_wdm_fabric
	python3 sim/check_hybrid_budget.py

hybrid-budget:
	python3 physical/hybrid_budget.py --output build/hybrid/bandwidth.json

.PHONY: hybrid-verilog hybrid-synth
$(SV2V): synth/hybrid.py tools.lock.json
	python3 synth/hybrid.py --sv2v $@ --install-only

hybrid-verilog: $(SV2V)
	mkdir -p build/hybrid
	python3 synth/hybrid.py --sv2v $(SV2V) $(COMMON_CELLS_SRC) $(FPNEW_SRC) \
		$(HYBRID_SRC) $(HYBRID_RTL)

hybrid-synth: hybrid-verilog
	@if [ ! -f build/hybrid/top.il ] || [ build/hybrid/top.v -nt build/hybrid/top.il ] || [ tools.lock.json -nt build/hybrid/top.il ]; then \
		$(HYBRID_YOSYS) -ql build/hybrid/top-synthesis.log -p 'read_verilog -sv build/hybrid/top.v; write_rtlil build/hybrid/top.tmp.il' && \
		mv build/hybrid/top.tmp.il build/hybrid/top.il; \
	fi
	@if [ ! -f build/hybrid/mux.il ] || [ build/hybrid/top.il -nt build/hybrid/mux.il ] || [ build/hybrid/components.v -nt build/hybrid/mux.il ]; then \
		$(HYBRID_YOSYS) -ql build/hybrid/mux-synthesis.log -p 'read_rtlil build/hybrid/top.il; read_verilog -sv -defer build/hybrid/components.v; hierarchy -check -top hybrid_top; proc_clean; proc_rmdead; proc_prune; proc_init; proc_arst; proc_rom; proc_mux; proc_clean; write_rtlil build/hybrid/mux.tmp.il' && \
		mv build/hybrid/mux.tmp.il build/hybrid/mux.il; \
	fi
	@if [ ! -f build/hybrid/core.il ] || [ build/hybrid/mux.il -nt build/hybrid/core.il ]; then \
		$(HYBRID_YOSYS) -ql build/hybrid/lower-synthesis.log -p 'read_rtlil build/hybrid/mux.il; opt_expr -keepdc; proc_dlatch; proc_dff; proc_memwr; proc_clean; opt_expr -keepdc; opt_clean; write_rtlil build/hybrid/core.tmp.il' && \
		mv build/hybrid/core.tmp.il build/hybrid/core.il; \
	fi
	@if [ ! -f build/hybrid/optimized.il ] || [ build/hybrid/core.il -nt build/hybrid/optimized.il ]; then \
		$(HYBRID_YOSYS) -ql build/hybrid/opt-synthesis.log -p 'read_rtlil build/hybrid/core.il; opt_clean -purge; opt -fast -noff -purge -keepdc; write_rtlil build/hybrid/optimized.tmp.il' && \
		mv build/hybrid/optimized.tmp.il build/hybrid/optimized.il; \
	fi
	$(HYBRID_YOSYS) -qL build/hybrid/synthesis.log -p 'read_rtlil build/hybrid/optimized.il; hierarchy -check -top hybrid_top; rename -hide; rename -enumerate; check -assert; stat; write_json build/hybrid/core.tmp.json'
	mv build/hybrid/core.tmp.json build/hybrid/core.json

hybrid-lint:
	verilator --lint-only --timing -DRISCV_FORMAL \
		-Ithird_party/common_cells/include -Wno-TIMESCALEMOD -Wno-WIDTHEXPAND \
		-Wno-WIDTHTRUNC -Wno-UNOPTFLAT -Wno-ASCRANGE -Wno-UNSIGNED --top-module hybrid_top \
		$(COMMON_CELLS_SRC) $(FPNEW_SRC) $(HYBRID_SRC) $(HYBRID_RTL)

hybrid-compile: $(STRESS_HEX)
	mkdir -p $(HYBRID_BUILD_DIR)
	verilator $(filter-out --trace,$(VERILATOR_FLAGS)) $(HYBRID_TRACE_FLAGS) $(HYBRID_VERILATOR_FLAGS) $(HYBRID_EXTRA_FLAGS) -DRISCV_FORMAL --top-module tb_top -j 4 \
		-Mdir $(HYBRID_BUILD_DIR) $(COMMON_CELLS_SRC) $(FPNEW_SRC) \
		$(HYBRID_SRC) $(HYBRID_RTL) $(TB_SRC)

hybrid-run: hybrid-compile
	$(HYBRID_BUILD_DIR)/Vtb_top
	$(HYBRID_BUILD_DIR)/Vtb_top +parallel_only
	$(HYBRID_BUILD_DIR)/Vtb_top +operators_only

.PHONY: hybrid-check hybrid-serial-check hybrid-cert
hybrid-check: hybrid-run hybrid-fabric-check hybrid-budget hybrid-lint

hybrid-serial-check:
	$(MAKE) hybrid-compile HYBRID_BUILD_DIR=build/verilator/hybrid-serial \
		HYBRID_EXTRA_FLAGS=-GFABRIC_BITS_PER_CYCLE=64
	build/verilator/hybrid-serial/Vtb_top
	build/verilator/hybrid-serial/Vtb_top +operators_only

hybrid-cert: architecture-cert

.PHONY: hybrid-formal
hybrid-formal: $(SV2V)
	mkdir -p build/hybrid
	$(SV2V) -EAlways -EAssert rtl/top/hybrid_pkg.sv rtl/photonic/wdm_fabric.sv \
		formal/hybrid_fabric.sv --top=hybrid_fabric_formal --top=hybrid_allocator_formal > build/hybrid/fabric-formal.v
	$(HYBRID_YOSYS) -ql build/hybrid/fabric-formal.log -p 'read_verilog -sv -formal build/hybrid/fabric-formal.v; prep -top hybrid_fabric_formal -flatten; memory_map; opt_clean; sat -seq 24 -set-init-zero -set-at 1 rst_n 0 -prove-asserts -verify'
	$(HYBRID_YOSYS) -ql build/hybrid/allocator-formal.log -p 'read_verilog -sv -formal build/hybrid/fabric-formal.v; prep -top hybrid_allocator_formal -flatten; opt; sat -prove-asserts -verify'

TB_SRC = sim/tb_top.sv

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

VERILATOR_FLAGS = --binary --timing $(HYBRID_TRACE_FLAGS) \
	-Ithird_party/common_cells/include -Wno-fatal -Wno-TIMESCALEMOD \
	-Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-UNOPTFLAT -Wno-ASCRANGE \
	-Wno-UNSIGNED

architecture-units:
	mkdir -p $(ARCH_DIR)
	iverilog -g2012 -s tb_arch_units -o $(ARCH_DIR)/units.vvp \
		rtl/top/hybrid_pkg.sv rtl/decode/decoder.sv rtl/decode/csr_file.sv sim/tb_arch_units.sv
	vvp $(ARCH_DIR)/units.vvp

extended-units:
	mkdir -p $(ARCH_DIR)
	iverilog -g2012 -s tb_extended_units -o $(ARCH_DIR)/extended.vvp \
		rtl/fetch/rvc_decompressor.sv rtl/execute/muldiv_unit.sv \
		sim/tb_extended_units.sv
	vvp $(ARCH_DIR)/extended.vvp

fpu-check:
	mkdir -p build/verilator/fpu
	verilator $(VERILATOR_FLAGS) --top-module tb_fpu \
		-Mdir build/verilator/fpu $(COMMON_CELLS_SRC) $(FPNEW_SRC) \
		rtl/execute/fpu_unit.sv sim/tb_fpu.sv
	build/verilator/fpu/Vtb_fpu

pmp-check:
	mkdir -p $(ARCH_DIR)
	iverilog -g2012 -s tb_pmp -o $(ARCH_DIR)/pmp.vvp \
		rtl/memory/pmp_checker.sv sim/tb_pmp.sv
	vvp $(ARCH_DIR)/pmp.vvp

sv32-check:
	mkdir -p $(ARCH_DIR)
	iverilog -g2012 -s tb_sv32 -o $(ARCH_DIR)/sv32.vvp \
		rtl/memory/sv32_mmu.sv sim/tb_sv32.sv
	vvp $(ARCH_DIR)/sv32.vvp

debug-check:
	mkdir -p $(ARCH_DIR)
	iverilog -g2012 -s tb_debug -o $(ARCH_DIR)/debug.vvp \
		rtl/debug/debug_control.sv sim/tb_debug.sv
	vvp $(ARCH_DIR)/debug.vvp

all: run
compile: hybrid-compile
run: hybrid-run
check: architecture-check hybrid-serial-check
formal-compile: hybrid-lint

architecture-check: hybrid-check architecture-units extended-units fpu-check \
	pmp-check sv32-check debug-check memory-check formal lint-check \
	jtag-cdc-check jtag-debug-check

formal: hybrid-formal
	sby -f -d build/formal/pmp formal/pmp.sby
	sby -f --sequential --prefix build/formal/safety formal/safety.sby

memory-check:
	mkdir -p $(ARCH_DIR)
	iverilog -g2012 -s tb_async_memory -o $(ARCH_DIR)/memory.vvp \
		rtl/memory/async_memory.sv sim/tb_async_memory.sv
	vvp $(ARCH_DIR)/memory.vvp

toolchain-check: act4-source softfloat-source praxis-source openocd-source
	python3 sim/check_toolchain.py

reproduce-check:
	$(MAKE) clean
	$(MAKE) toolchain-check architecture-cert

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
ACT4_ELFS = $(ACT4_SRC)/$(ACT4_WORK)/photonic-rv32gc/elfs
ACT4_HEX = $(ACT4_DIR)/hex-rv32gc
ACT4_JOBS ?= 8
ACT4_TIMEOUT ?= 30000000
RVFI_INST_LIMIT ?= 100000
OS_TIMEOUT ?= 20000000
ACT4_VERILATOR_DIR = build/verilator/hybrid/act4
ACT4_BIN = $(ACT4_VERILATOR_DIR)/Vtb_act4
HYBRID_COUNTER_DIR = $(ACT4_SRC)/work/hybrid-counter/photonic-rv32gc/elfs/priv/Sm
HYBRID_COUNTER_HEX = build/hybrid/Sm_mcsr_cntr-00.hex
SOFTFLOAT_REV = a0c6494cdc11865811dec815d5c0049fba9d82a8
SOFTFLOAT_SRC = build/softfloat/source
SOFTFLOAT_BUILD = $(SOFTFLOAT_SRC)/build/Linux-x86_64-GCC
SOFTFLOAT_RISCV = $(SOFTFLOAT_BUILD)/.riscv-specialization
BOOT_ELF = $(PROGRAM_DIR)/architecture_boot.elf
BOOT_HEX = $(PROGRAM_DIR)/architecture_boot.hex
PRAXIS_REV = 277bd2b21124722209b93af3ec82ea182a22d79c
PRAXIS_DIR = build/praxis
PRAXIS_SRC = $(PRAXIS_DIR)/source
PRAXIS_WORK = $(PRAXIS_DIR)/work
PRAXIS_PATCHED = $(PRAXIS_WORK)/.photonic-port
PRAXIS_BUILD = $(PRAXIS_WORK)/build
PRAXIS_ELF = $(PRAXIS_BUILD)/praxis.elf
PRAXIS_BIN = $(PRAXIS_BUILD)/praxis.bin
PRAXIS_HEX = $(PRAXIS_BUILD)/praxis.hex
OPENOCD_REV = 9ea7f3d647c8ecf6b0f1424002dfc3f4504a162c
OPENOCD_DIR = build/openocd
OPENOCD_SRC = $(OPENOCD_DIR)/source
OPENOCD_BIN = $(OPENOCD_SRC)/src/openocd
OPENOCD_VERILATOR_DIR = build/verilator/hybrid/openocd
OPENOCD_SERVER = $(OPENOCD_VERILATOR_DIR)/Vtop_jtag
INTERRUPT_ELF = $(PROGRAM_DIR)/interrupt_diff.elf
INTERRUPT_HEX = $(PROGRAM_DIR)/interrupt_diff.hex
INTERRUPT_TOHOST = $(PROGRAM_DIR)/interrupt_diff.tohost

.PHONY: act4-source act4-config act4-elfs act4-compile act4-hex \
	act4-official softfloat-source softfloat-check boot-image boot-check \
	praxis-source os-image os-check \
	rvfi-diff interrupt-image lint-check jtag-cdc-check jtag-debug-check \
	openocd-source openocd-debug-check architecture-cert

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
	cp --remove-destination $(ACT4_SRC)/config/sail/sail-rv32-max/rvmodel_macros.h \
		$(ACT4_CONFIG_DIR)/rvmodel_macros.h
	sed -i -e 's/RVMODEL_TIMER_INT_SOON_DELAY 100/RVMODEL_TIMER_INT_SOON_DELAY 1000/' \
		-e 's/RVMODEL_MAX_CYCLES_PER_TIMER_TICK 1/RVMODEL_MAX_CYCLES_PER_TIMER_TICK 16/' \
		$(ACT4_CONFIG_DIR)/rvmodel_macros.h
	cp --remove-destination $(ACT4_SRC)/config/sail/sail-RVI20U32/sail.json \
		$(ACT4_CONFIG_DIR)/sail.json
	sed -i -e 's/"writable_fiom": true/"writable_fiom": false/' \
		-e '/"scounteren_writable_bits": {/,/}/{s/"value": "0x0"/"value": "0x7"/;}' \
		-e '/"mcounteren_writable_bits": {/,/}/{s/"value": "0x0"/"value": "0x7"/;}' \
		-e '/"stvec": {/,/"medeleg": {/s/"supported": false/"supported": true/' \
		-e 's/0x0000_0000_000c_b3FF/0x0000_0000_0000_b3FF/' \
		-e 's/"value": "0x0000_2222"/"value": "0x0000_0222"/' \
		-e 's/"software_breakpoint": true/"software_breakpoint": false/' \
		-e 's/"hardware_breakpoint": true/"hardware_breakpoint": false/' \
		-e 's/"count": 0/"count": 16/' \
		-e 's/"usable_count": 0/"usable_count": 4/' \
		-e '/"load_store": {/{n;s/"None": null/"Some": "AlignmentException"/;}' \
		-e '/"amo": {/{n;s/"Some": "AccessFault"/"Some": "AlignmentException"/;}' \
		-e 's/"lrsc": "AccessFault"/"lrsc": "AlignmentException"/' \
		-e 's/"atomic_support": "AMOCASQ"/"atomic_support": "AMOArithmetic"/' \
		-e 's/"fflags_dirty_policy": "Fflags_Dirty_Precise"/"fflags_dirty_policy": "Fflags_Dirty_Instruction"/' \
		-e '/"S": {/,/}/{s/"supported": false/"supported": true/;}' \
		-e '/"U": {/,/}/{s/"supported": false/"supported": true/;}' \
		-e '/"Zihpm": {/,/}/{s/"supported": true/"supported": false/;}' \
		-e '/"Svadu": {/,/}/{s/"supported": false/"supported": true/;}' \
		-e '/"Svbare": {/,/}/{s/"supported": false/"supported": true/;}' \
		-e '/"Sv32": {/,/}/{s/"supported": false/"supported": true/;}' \
		$(ACT4_CONFIG_DIR)/sail.json

act4-elfs: act4-config
	docker run --rm -v $(abspath $(ACT4_SRC)):/act4 -w /act4 \
		$(ACT4_IMAGE) make CONFIG_FILES=$(ACT4_CONFIG) \
		WORKDIR=$(ACT4_WORK) FAST=True -j8

act4-compile:
	mkdir -p $(ACT4_VERILATOR_DIR)
	verilator $(VERILATOR_FLAGS) $(HYBRID_VERILATOR_FLAGS) -j 4 -DRISCV_FORMAL --top-module tb_act4 \
		-Mdir $(ACT4_VERILATOR_DIR) $(COMMON_CELLS_SRC) $(FPNEW_SRC) \
		$(RTL_SRC) sim/tb_act4.sv

act4-hex: act4-elfs
	mkdir -p $(ACT4_HEX)
	docker run --rm -v $(abspath $(ACT4_SRC)):/act4:ro \
		-v $(abspath $(ACT4_HEX)):/hex $(ACT4_IMAGE) sh -c \
		'find /act4/$(ACT4_WORK)/photonic-rv32gc/elfs -name "*.elf" | while read elf; do \
			ext=$$(basename "$$(dirname "$$elf")"); name=$$(basename "$$elf" .elf); \
			mkdir -p "/hex/$$ext"; \
		riscv64-unknown-elf-objcopy -O verilog --verilog-data-width=1 \
			"$$elf" "/hex/$$ext/$$name.hex"; \
		riscv64-unknown-elf-nm "$$elf" | grep " tohost$$" | cut -d" " -f1 \
			> "/hex/$$ext/$$name.tohost"; \
		sed -i "s/^@8/@0/" "/hex/$$ext/$$name.hex"; \
		done'

.PHONY: hybrid-counter-image
hybrid-counter-image: act4-hex
	python3 sim/act4/hybrid_counter.py
	docker run --rm -v $(abspath $(ACT4_SRC)):/act4 -w /act4 $(ACT4_IMAGE) \
		mise exec -- uv run act $(ACT4_CONFIG) --workdir work/hybrid-counter \
		--test-dir work/hybrid-counter/tests --fast
	mkdir -p build/hybrid
	docker run --rm -v $(abspath .):/cpu -w /cpu $(ACT4_IMAGE) \
		riscv64-unknown-elf-objcopy -O verilog --verilog-data-width=1 \
		$(HYBRID_COUNTER_DIR)/Sm_mcsr_cntr-00.elf $(HYBRID_COUNTER_HEX)
	llvm-nm $(HYBRID_COUNTER_DIR)/Sm_mcsr_cntr-00.elf | awk '/ tohost$$/{print $$1}' > $(HYBRID_COUNTER_HEX:.hex=.tohost)
	sed -i 's/^@8/@0/' $(HYBRID_COUNTER_HEX)

act4-official: act4-compile act4-hex hybrid-counter-image
	@echo "ACT4 hybrid profile: counter test uses the documented 100000-cycle timing bound"
	@mkdir -p $(ACT4_DIR)/logs; \
	find $(ACT4_HEX) -name '*.hex' -print0 | sort -z | \
		xargs -0 -n1 -P$(ACT4_JOBS) sh -c ' \
			hex="$$1"; name=$${hex##*/}; name=$${name%.hex}; \
			log="$(ACT4_DIR)/logs/$${hex#$(ACT4_HEX)/}"; log=$${log%.hex}.log; \
			if [ "$$name" = Sm_mcsr_cntr-00 ]; then hex="$(HYBRID_COUNTER_HEX)"; fi; \
			tohost=$$(cat "$${hex%.hex}.tohost"); \
			mkdir -p "$${log%/*}"; \
			if $(ACT4_BIN) +hex="$$hex" +test="$$name" +tohost="$$tohost" +reset_high +timeout=$(ACT4_TIMEOUT) >"$$log" 2>&1; then \
				echo "PASS $$name"; \
			else \
				echo "FAIL $$name ($$log)"; exit 1; \
			fi' _ >$(ACT4_DIR)/official-results.log; \
	status=$$?; cat $(ACT4_DIR)/official-results.log; \
	total=$$(wc -l <$(ACT4_DIR)/official-results.log); \
	passed=$$(grep -c '^PASS ' $(ACT4_DIR)/official-results.log || true); \
	echo "ACT4 configured ISA: $$passed/$$total passed"; \
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
		rtl/execute/fpu_unit.sv sim/tb_fpu_random.sv \
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

praxis-source:
	@if [ ! -d $(PRAXIS_SRC)/.git ]; then \
		git clone --filter=blob:none https://github.com/fibonatto/PraxisOS.git $(PRAXIS_SRC); \
		git -C $(PRAXIS_SRC) checkout --detach $(PRAXIS_REV); \
	fi
	@test "$$(git -C $(PRAXIS_SRC) rev-parse HEAD)" = "$(PRAXIS_REV)"

$(PRAXIS_PATCHED): praxis-source sim/os/praxis.patch
	rm -rf $(PRAXIS_WORK)
	cp -a $(PRAXIS_SRC) $(PRAXIS_WORK)
	git -C $(PRAXIS_WORK) apply $(abspath sim/os/praxis.patch)
	touch $@

$(PRAXIS_HEX): $(PRAXIS_PATCHED) sim/os/praxis_boot.S sim/os/praxis_qualification.c
	mkdir -p $(PRAXIS_BUILD)
	clang -std=c11 -O2 --target=riscv32-unknown-elf -march=rv32im -mabi=ilp32 \
		-fuse-ld=lld -fno-stack-protector -ffreestanding -nostdlib \
		-I$(PRAXIS_WORK)/include -Wl,-T$(PRAXIS_WORK)/src/user.ld \
		-o $(PRAXIS_BUILD)/shell.elf sim/os/praxis_qualification.c \
		$(PRAXIS_WORK)/src/user.c $(PRAXIS_WORK)/src/common.c
	llvm-objcopy --set-section-flags .bss=alloc,contents -O binary \
		$(PRAXIS_BUILD)/shell.elf $(PRAXIS_BUILD)/shell.bin
	cd $(PRAXIS_BUILD) && llvm-objcopy -Ibinary -Oelf32-littleriscv shell.bin shell.bin.o
	clang -std=c11 -O2 --target=riscv32-unknown-elf -march=rv32im -mabi=ilp32 \
		-fuse-ld=lld -fno-stack-protector -ffreestanding -nostdlib \
		-I$(PRAXIS_WORK)/include -Wl,-T$(PRAXIS_WORK)/src/kernel.ld \
		-o $(PRAXIS_ELF) sim/os/praxis_boot.S $(PRAXIS_WORK)/src/kernel.c \
		$(PRAXIS_WORK)/src/common.c $(PRAXIS_WORK)/src/context.c \
		$(PRAXIS_WORK)/src/process.c $(PRAXIS_WORK)/src/memory.c \
		$(PRAXIS_WORK)/src/sbi.c $(PRAXIS_BUILD)/shell.bin.o
	llvm-objcopy -O binary $(PRAXIS_ELF) $(PRAXIS_BIN)
	od -An -v -tx1 -w1 $(PRAXIS_BIN) > $(PRAXIS_HEX)

os-image: $(PRAXIS_HEX)

os-check: act4-compile os-image
	$(ACT4_BIN) +hex=$(PRAXIS_HEX) +test=praxis-sv32 +require_os +timeout=$(OS_TIMEOUT)

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
	verilator --lint-only --timing $(CORE_DEFINES) --top-module top_jtag \
		-Wall -Wno-fatal -Wno-TIMESCALEMOD \
		-Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-UNOPTFLAT -Wno-ASCRANGE \
		-Wno-UNSIGNED -Ithird_party/common_cells/include rtl/lint.vlt \
		$(COMMON_CELLS_SRC) $(FPNEW_SRC) $(RTL_SRC) rtl/top/top_jtag.sv

jtag-cdc-check:
	mkdir -p build/cdc
	$(HYBRID_YOSYS) -q -s synth/jtag_cdc.ys
	python3 sim/check_jtag_cdc.py

jtag-debug-check:
	mkdir -p $(ARCH_DIR)
	iverilog -g2012 -s tb_jtag_debug -o $(ARCH_DIR)/jtag_debug.vvp \
		rtl/debug/riscv_debug_transport.sv sim/tb_jtag_debug.sv
	vvp $(ARCH_DIR)/jtag_debug.vvp

openocd-source:
	@if [ ! -d $(OPENOCD_SRC)/.git ]; then \
		git clone --filter=blob:none https://github.com/openocd-org/openocd.git $(OPENOCD_SRC); \
		git -C $(OPENOCD_SRC) checkout --detach $(OPENOCD_REV); \
		git -C $(OPENOCD_SRC) submodule update --init --depth 1; \
	fi
	@test "$$(git -C $(OPENOCD_SRC) rev-parse HEAD)" = "$(OPENOCD_REV)"

$(OPENOCD_BIN): openocd-source
	cd $(OPENOCD_SRC) && ./bootstrap
	cd $(OPENOCD_SRC) && ./configure --enable-remote-bitbang \
		--disable-internal-libjaylink --disable-werror
	$(MAKE) -C $(OPENOCD_SRC) -j1

$(OPENOCD_SERVER): sim/openocd_server.cpp $(RTL_SRC) rtl/top/top_jtag.sv rtl/top/hybrid_rob_update.svh
	mkdir -p $(OPENOCD_VERILATOR_DIR)
	verilator --cc --exe --build -j 4 $(CORE_DEFINES) $(HYBRID_VERILATOR_FLAGS) -Ithird_party/common_cells/include \
		-Wno-fatal -Wno-TIMESCALEMOD -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
		-Wno-UNOPTFLAT -Wno-ASCRANGE -Wno-UNSIGNED --top-module top_jtag \
		-Mdir $(OPENOCD_VERILATOR_DIR) $(COMMON_CELLS_SRC) $(FPNEW_SRC) \
		$(RTL_SRC) rtl/top/top_jtag.sv $(abspath sim/openocd_server.cpp)

openocd-debug-check: $(OPENOCD_BIN) $(OPENOCD_SERVER)
	python3 sim/run_openocd_test.py $(OPENOCD_SERVER) $(OPENOCD_BIN) \
		$(abspath $(OPENOCD_SRC)/tcl)

architecture-cert: architecture-check hybrid-serial-check openocd-debug-check \
	act4-official rvfi-diff softfloat-check boot-check os-check
