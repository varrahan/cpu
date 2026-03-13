CC = iverilog
SIM = vvp
OUT = sim/top_sim.vvp
WAVE = sim/top_wave.vcd

FETCH_SRC = rtl/fetch/fetch_stage.v

DECODE_SRC = rtl/decode/decoder.v \
             rtl/decode/regfile.v \
             rtl/decode/decode_execute_register.v

EXEC_SRC = rtl/execute/alu.v \
           rtl/execute/branch_unit.v \
           rtl/execute/forwarding_unit.v \
           rtl/execute/hazard_unit.v \
           rtl/execute/execute_memory_register.v

MEM_SRC = rtl/memory/memory_stage.v \
          rtl/memory/memory_writeback_register.v

WB_SRC = rtl/writeback/writeback_stage.v

TOP_SRC = rtl/top/top.v

RTL_SRC = $(FETCH_SRC) $(DECODE_SRC) $(EXEC_SRC) $(MEM_SRC) $(WB_SRC) $(TOP_SRC)

TB_SRC = sim/tb_top.v

all: compile run
compile:
	@echo "Compiling RTL and Testbench..."
	$(CC) -g2012 -o $(OUT) $(RTL_SRC) $(TB_SRC)

run:
	@echo "Running Simulation..."
	$(SIM) $(OUT)

clean:
	rm -f $(OUT) $(WAVE)

	@echo "Clean complete."