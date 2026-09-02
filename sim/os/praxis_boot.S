    .section .text.mboot
    .globl _start
_start:
    li t0, -1
    csrw pmpaddr0, t0
    li t0, 0x1f
    csrw pmpcfg0, t0
    li t0, (1 << 8) | (1 << 12) | (1 << 13) | (1 << 15)
    csrw medeleg, t0
    la t0, machine_trap
    csrw mtvec, t0
    li t0, 0x00200000
    csrw mepc, t0
    csrr t0, mstatus
    li t1, ~(3 << 11)
    and t0, t0, t1
    li t1, (1 << 11)
    or t0, t0, t1
    csrw mstatus, t0
    mret

    .align 2
machine_trap:
    csrr t0, mcause
    li t1, 9
    bne t0, t1, machine_fail
    li t0, 1
    beq a7, t0, console_putchar
    li t0, 2
    beq a7, t0, console_getchar
    li a0, -2
    j machine_return
console_putchar:
    li t0, 0x10000000
    sw a0, 0(t0)
    li a0, 0
    j machine_return
console_getchar:
    li a0, -1
machine_return:
    csrr t0, mepc
    addi t0, t0, 4
    csrw mepc, t0
    mret
machine_fail:
    li t1, 0x20000000
    sw t0, 0(t1)
1:  j 1b
