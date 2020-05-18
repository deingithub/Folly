# This is the interrupt handler prologue and epilogue. It passes control
# to Zig's rupt.zig_rupt() and creates/restores the kernel trap frame.

# this directive enables %i a few lines below
.altmacro
# assembly, now with even less effort!
.macro save_x_register i
    sd x\i, \i*8(t6)
.endm
.macro load_x_register i
    ld x\i, \i*8(t6)
.endm


.global asm_rupt
asm_rupt:
    # the pointer to our frame is in mscratch.
    # to get it, swap t6 (the last register) and mscratch
    csrrw t6, mscratch, t6
    # initialize trap frame:
    # save first 31 general purpose registers
    .set i, 0
    .rept 31
        save_x_register %i
        .set i, i+1
    .endr
    # now, save t6:
    # move mscratch value from t6 into t5
    mv t5, t6
    # move t6 value out of mscratch
    csrr t6, mscratch
    # save t6
    sd t6, 31*8(t5)
    # tidy up:
    # move mscratch value from t5 back into mscratch
    csrw mscratch, t5

    # arguments for zig: cause, exception program counter, trap value, frame
    csrr a0, mcause
    csrr a1, mepc
    csrr a2, mtval
    csrr a3, mscratch
    # set up stack pointer from the frame and ~ jump away ~
    ld sp, 256(a3)
    call zig_rupt

    # welcome back!
    # write back our updated EPC
    csrw mepc, a0

    # the above but the other way around, also this time we just overwrite t6
    # instead of special-casing it. yay.
    csrr t6, mscratch

    .set i, 1
    .rept 31
        load_x_register %i
        .set i, i+1
    .endr

    mret
