    .section .text.init
    .globl _start
_start:
    la sp, stack_top
    la t0, root_page_table
    li t1, 0
    li t2, 1024
1:  sw t1, 0(t0)
    addi t0, t0, 4
    addi t2, t2, -1
    bnez t2, 1b
    la t0, root_page_table
    li t1, 0x000000cf
    sw t1, 0(t0)
    sw t1, 1024(t0)
    li t1, 0x080000cf
    sw t1, 512(t0)
    li t0, -1
    csrw pmpaddr0, t0
    li t0, 0x1f
    csrw pmpcfg0, t0
    la t0, machine_trap
    csrw mtvec, t0
    la t0, supervisor_trap
    csrw stvec, t0
    la t0, root_page_table
    srli t0, t0, 12
    li t1, 0x80000000
    or t0, t0, t1
    csrw satp, t0
    sfence.vma
    csrr t0, mstatus
    li t1, ~(3 << 11)
    and t0, t0, t1
    li t1, (1 << 11)
    or t0, t0, t1
    csrw mstatus, t0
    la t0, supervisor_entry
    csrw mepc, t0
    mret
supervisor_entry:
    la t0, signature
    li t1, 0x40000000
    add t1, t1, t0
    li t2, 0x51a7c0de
    sw t2, 0(t1)
    lw t3, 0(t0)
    bne t2, t3, supervisor_fail
    csrr t4, sstatus
    li t0, 0x20000000
    li t1, 123456789
    sw t1, 0(t0)
2:  j 2b
    .align 2
supervisor_fail:
supervisor_trap:
    li t0, 0x20000000
    csrr t1, scause
    ori t1, t1, 0x100
    sw t1, 0(t0)
3:  j 3b
    .align 2
machine_trap:
    li t0, 0x20000000
    csrr t1, mcause
    sw t1, 0(t0)
4:  j 4b
    .section .data
    .align 2
signature: .word 0
    .section .bss
    .align 12
root_page_table: .space 4096
    .align 4
stack: .space 4096
stack_top:
