#!/usr/bin/env python3
"""Require the compiled stress image to retain every exercised ISA family."""

import sys
from pathlib import Path


REQUIRED = set("""
lui auipc jal jalr beq bne blt bge bltu bgeu
lb lh lw lbu lhu sb sh sw
addi slti sltiu xori ori andi slli srli srai
add sub sll slt sltu xor srl sra or and
fence fence.i wfi
mul mulh mulhsu mulhu div divu rem remu
lr.w sc.w amoswap.w amoadd.w amoxor.w amoand.w amoor.w
amomin.w amomax.w amominu.w amomaxu.w
csrrw csrrs csrrc csrrwi csrrsi csrrci
flw fsw fmadd.s fmsub.s fnmsub.s fnmadd.s
fadd.s fsub.s fmul.s fdiv.s fsqrt.s fsgnj.s fsgnjn.s fsgnjx.s
fmin.s fmax.s feq.s flt.s fle.s fcvt.w.s fcvt.wu.s
fcvt.s.w fcvt.s.wu fmv.x.w fmv.w.x fclass.s
fld fsd fmadd.d fmsub.d fnmsub.d fnmadd.d
fadd.d fsub.d fmul.d fdiv.d fsqrt.d fsgnj.d fsgnjn.d fsgnjx.d
fmin.d fmax.d feq.d flt.d fle.d fcvt.w.d fcvt.wu.d
fcvt.d.w fcvt.d.wu fcvt.s.d fcvt.d.s fclass.d
""".split())


def main():
    dump = Path(sys.argv[1] if len(sys.argv) > 1
                else "build/programs/rv32gc_stress.dump").read_text()
    mnemonics = {
        fields[1].strip() for line in dump.splitlines()
        if len(fields := line.split("\t")) > 1
    }
    missing = sorted(REQUIRED - mnemonics)
    if missing:
        raise SystemExit("FAIL: stress image lost instructions: " +
                         ", ".join(missing))
    compressed = sum(
        len(line.split("\t", 1)[0].split(":", 1)[-1].split()) == 2
        for line in dump.splitlines() if "\t" in line
    )
    if compressed < 32:
        raise SystemExit(f"FAIL: only {compressed} compressed instructions")
    print(f"PASS: stress image covers {len(REQUIRED)} ISA mnemonics and "
          f"{compressed} compressed instructions")


if __name__ == "__main__":
    main()
