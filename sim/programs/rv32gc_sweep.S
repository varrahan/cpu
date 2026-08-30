    .section .text
    .option push
    .option norvc
    .global isa_sweep
isa_sweep:
    # Every RV32M operation contributes to a checked signature.
    li      t0, -7
    li      t1, 3
    mul     t2, t0, t1
    mulh    t3, t0, t1
    xor     t2, t2, t3
    mulhsu  t3, t0, t1
    xor     t2, t2, t3
    mulhu   t3, t0, t1
    xor     t2, t2, t3
    div     t3, t0, t1
    xor     t2, t2, t3
    divu    t3, t0, t1
    xor     t2, t2, t3
    rem     t3, t0, t1
    xor     t2, t2, t3
    remu    t3, t0, t1
    xor     t2, t2, t3
    sw      t2, 100(a0)

    # Base integer ALU, immediate, byte/half/word memory, and branch forms.
    addi    t0, t0, 5
    slti    t1, t0, 0
    sltiu   t2, t0, 1
    xori    t3, t0, 0x55
    ori     t4, t0, 0x20
    andi    t5, t0, 0x7f
    slli    t3, t3, 3
    srli    t4, t4, 2
    srai    t5, t5, 1
    add     t6, t3, t4
    sub     t6, t6, t5
    sll     t3, t3, t1
    slt     t4, t0, t1
    sltu    t5, t0, t1
    xor     t6, t6, t3
    srl     t3, t6, t1
    sra     t4, t6, t1
    or      t5, t3, t4
    and     t6, t6, t5
    sw      t6, 108(a0)

    addi    t4, a0, 112
    li      t5, 0x80ff7f01
    sw      t5, 0(t4)
    lb      t0, 0(t4)
    lbu     t1, 1(t4)
    lh      t2, 2(t4)
    lhu     t3, 2(t4)
    sb      t1, 4(t4)
    sh      t3, 6(t4)
    sw      t5, 8(t4)
    lw      t6, 8(t4)

    li      t0, -7
    li      t1, 3
    beq     t0, t1, .Lbase_fail
    bne     t0, t1, .Lbranch_blt
.Lbase_fail:
    sw      zero, 104(a0)
    j       .Lfp
.Lbranch_blt:
    blt     t0, t1, .Lbranch_bge
    j       .Lbase_fail
.Lbranch_bge:
    bge     t1, t0, .Lbranch_bltu
    j       .Lbase_fail
.Lbranch_bltu:
    bltu    t1, t0, .Lbranch_bgeu
    j       .Lbase_fail
.Lbranch_bgeu:
    bgeu    t0, t1, .Lbranch_jal
    j       .Lbase_fail
.Lbranch_jal:
    jal     t2, .Lbranch_jalr
    j       .Lbase_fail
.Lbranch_jalr:
    la      t3, .Lbase_pass
    jalr    t2, 0(t3)
    j       .Lbase_fail
.Lbase_pass:
    lui     t3, 0x51
    auipc   t4, 0
    addi    t3, t3, 0x5e
    sw      t3, 104(a0)

.Lfp:
    # Every RV32F arithmetic, fused, sign, compare, convert, move, and class op.
    li      t0, 3
    li      t1, 4
    fcvt.s.w    ft0, t0
    fcvt.s.wu   ft1, t1
    fadd.s      ft2, ft0, ft1
    fsub.s      ft3, ft1, ft0
    fmul.s      ft4, ft0, ft1
    fdiv.s      ft5, ft1, ft0
    fsqrt.s     ft6, ft1
    fsw         ft6, 80(a0)
    flw         ft7, 80(a0)
    fmadd.s     ft8, ft0, ft1, ft2
    fmsub.s     ft9, ft0, ft1, ft2
    fnmsub.s    ft10, ft0, ft1, ft2
    fnmadd.s    ft11, ft0, ft1, ft2
    fsgnj.s     ft8, ft0, ft1
    fsgnjn.s    ft9, ft0, ft1
    fsgnjx.s    ft10, ft0, ft1
    fmin.s      ft8, ft0, ft1
    fmax.s      ft9, ft0, ft1
    feq.s       t2, ft0, ft1
    flt.s       t3, ft0, ft1
    fle.s       t4, ft0, ft1
    fcvt.w.s    t2, ft2, rtz
    fcvt.wu.s   t3, ft2, rtz
    fmv.x.w     t4, ft0
    fmv.w.x     ft10, t4
    fclass.s    t5, ft0

    # Every RV32D counterpart plus the S/D cross-format conversions.
    fcvt.d.w    ft0, t0
    fcvt.d.wu   ft1, t1
    fadd.d      ft2, ft0, ft1
    fsd         ft2, 88(a0)
    fld         ft3, 88(a0)
    fsub.d      ft3, ft1, ft0
    fmul.d      ft4, ft0, ft1
    fdiv.d      ft5, ft1, ft0
    fsqrt.d     ft6, ft1
    fmadd.d     ft8, ft0, ft1, ft2
    fmsub.d     ft9, ft0, ft1, ft2
    fnmsub.d    ft10, ft0, ft1, ft2
    fnmadd.d    ft11, ft0, ft1, ft2
    fsgnj.d     ft8, ft0, ft1
    fsgnjn.d    ft9, ft0, ft1
    fsgnjx.d    ft10, ft0, ft1
    fmin.d      ft8, ft0, ft1
    fmax.d      ft9, ft0, ft1
    feq.d       t2, ft0, ft1
    flt.d       t3, ft0, ft1
    fle.d       t4, ft0, ft1
    fcvt.w.d    t2, ft2, rtz
    fcvt.wu.d   t3, ft2, rtz
    fcvt.s.d    ft10, ft0
    fcvt.d.s    ft11, ft10
    fclass.d    t5, ft0
    sw          t5, 96(a0)
    ret
    .option pop
