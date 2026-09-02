    .section .text.init
    .globl _start
_start:
    la t0, trap
    csrw mtvec, t0
    li t0, (1 << 11)
    csrs mie, t0
    li t0, (1 << 3)
    csrs mstatus, t0
    li t0, 0x0c000004
    li t1, 0x80000800
    sw t1, 0(t0)
interrupt_wait:
    j interrupt_wait

trap:
    csrr t0, mcause
    li t1, 0x8000000b
    bne t0, t1, fail
    li t0, (1 << 11)
    csrc mie, t0
    li t0, 0x0c000004
    li t1, 0x00000800
    sw t1, 0(t0)
    la t0, tohost
    li t1, 1
    sw t1, 0(t0)
    sw zero, 4(t0)
1:  j 1b

fail:
    la t0, tohost
    li t1, 3
    sw t1, 0(t0)
    sw zero, 4(t0)
2:  j 2b

    .section .tohost,"aw",@progbits
    .align 3
    .globl tohost
tohost:
    .word 0, 0
