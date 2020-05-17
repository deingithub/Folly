.section .data
.option norvc

# goddess, sing of the wrath of Page-Fault Exception
.section .text.proem

.global _start
_start:
    # read hart id
    csrr t0, mhartid
    # jump into wait for interrupt loop if it's not 0
    bnez t0, youspinmeround
    # zero out SATP CSR
    csrw satp, zero

    # set up global pointer
    .option push
    .option norelax
    la gp, __global_pointer
    .option pop

    # store start and end of bss
    la a0, __bss_start
    la a1, __bss_end

    # If bss is done already, skip
    bgeu a0, a1, fill_bss_done

    # loop until all bss is filled with zeroes
    fill_bss_start:
        sd zero, (a0)
        addi a0, a0, 8
        bltu a0, a1, fill_bss_start
    fill_bss_done:

    # set stack pointer
    la sp, __stack_top
    # set machine mode and enable interrupts
    li t0, (1 << 12) | (1 << 11) | (1 << 7) | (1 << 3)
    csrw mstatus, t0
    # set trap return to kmain
    la t1, kmain
    csrw mepc, t1
    # set up interrupt handler
    la t2, interrupt_vec
    csrw mtvec, t2
    # enable interrupts
    li t3, (1 << 11) | (1 << 7) | (1 << 3)
    csrw mie, t3
    # set return address to wait for interrupt loop
    la ra, youspinmeround
    # jump into kmain
    mret

# hart go spinny uwu
youspinmeround:
    wfi
    j youspinmeround

# TODO this fucks over whichever poor sod was working when an interrupt happened
.global interrupt_vec
interrupt_vec:
    csrr a0, mcause
    csrr a1, mepc
    call interrupt
    mret