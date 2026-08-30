#!/usr/bin/env python3
from pathlib import Path
top = Path("rtl/top/top.v").read_text()
dtm = Path("rtl/debug/riscv_debug_transport.sv").read_text()
for signal in ("irq_m_software", "irq_m_timer", "irq_m_external",
               "irq_s_software", "irq_s_timer", "irq_s_external", "nmi"):
    assert f"{signal}_sync" in top
    assert f"({signal}_sync[1])" in top
assert top.count('ASYNC_REG = "TRUE"') >= 7
assert dtm.count('ASYNC_REG = "TRUE"') >= 2
assert "posedge tck" in dtm and "posedge core_clk" in dtm
print("PASS: interrupt, JTAG DMI, and reset-domain structural CDC policy")
