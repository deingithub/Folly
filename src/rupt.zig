//! This file contains the top level interrupt handler

const std = @import("std");

const uart = @import("./uart.zig");
const heap = @import("./heap.zig");
pub const Timer = @import("./rupt/timer.zig");
pub const PLIC = @import("./rupt/plic.zig");

const debug = @import("build_options").log_rupt;

/// Initialize all necessary values. Must be called as early as possible
/// after UART is available.
pub fn init() void {
    const k_trap_stack = heap.allocPages(10) catch @panic("Kernel OOM while trying to allocate kernel trap stack in rupt.init()");
    kframe.trap_stack = &(k_trap_stack[k_trap_stack.len - 1]);

    if (comptime debug)
        uart.print("init interrupts...\n", .{});

    Timer.init();
    PLIC.init();
}

const TrapFrame = extern struct {
    regs: [31]usize, // byte 0-247
    trap_stack: *u8, // byte 248-255
    hartid: usize, // byte 256-263
};

export var kframe linksection(".bss") = TrapFrame{
    .regs = [_]usize{0} ** 31,
    .trap_stack = undefined,
    .hartid = 0,
};

fn asyncInterrupt(comptime n: u63) u64 {
    return (1 << 63) + @as(usize, n);
}
fn syncInterrupt(comptime n: u63) u64 {
    return (0 << 63) + @as(usize, n);
}

/// This *ought* to be a non-exhaustive enum because the spec allows
/// implementation-defined interrupts, but why would I bother with that.
pub const InterruptCause = enum(u64) {
    // Asynchronous Interrupts
    user_software = asyncInterrupt(0),
    supervisor_software = asyncInterrupt(1),
    // asyncInterrupt(2) reserved
    machine_software = asyncInterrupt(3),
    user_timer = asyncInterrupt(4),
    supervisor_timer = asyncInterrupt(5),
    // asyncInterrupt(6) reserved
    machine_timer = asyncInterrupt(7),
    user_external = asyncInterrupt(8),
    supervisor_external = asyncInterrupt(9),
    // asyncInterrupt(10) reserved
    machine_external = asyncInterrupt(11),
    // Synchronous Interrupts
    instruction_address_misaligned = syncInterrupt(0),
    instruction_access_faul = syncInterrupt(1),
    illegal_instruction = syncInterrupt(2),
    breakpoint = syncInterrupt(3),
    load_address_misaligned = syncInterrupt(4),
    load_access_fault = syncInterrupt(5),
    store_amo_address_misaligned = syncInterrupt(6),
    store_amo_access_fault = syncInterrupt(7),
    environment_call_from_user = syncInterrupt(8),
    environment_call_from_supervisor = syncInterrupt(9),
    // syncInterrupt(10) reserved
    environment_call_from_machine = syncInterrupt(11),
    instruction_page_fault = syncInterrupt(12),
    load_page_fault = syncInterrupt(13),
    // syncInterrupt(14) reserved
    store_amo_page_fault = syncInterrupt(15),
};

/// The interrupt vector that the processor jumps to
export fn rupt() align(4) callconv(.Naked) void {
    comptime {
        std.debug.assert(@sizeOf(TrapFrame) == 264); // when this fails, adjust the code below!
    }

    // atomically swap trap frame address into t6
    asm volatile ("csrrw t6, mscratch, t6");

    // save first 30 general purpose registers that aren't x0 into the trap frame
    comptime var save_reg = 1;
    inline while (save_reg < 31) : (save_reg += 1) {
        @setEvalBranchQuota(11000);
        comptime var buf = [_]u8{0} ** 32;
        asm volatile (comptime std.fmt.bufPrint(
            &buf,
            "sd x{}, {}(t6)",
            .{ save_reg, (save_reg - 1) * 8 },
        ) catch unreachable);
    }
    // save register x31
    asm volatile (
        \\mv t5, t6
        \\sd t6, 30*8(t5)
        \\csrw mscratch, t5
    );
    // clean slate. set up arguments and call the main handler
    asm volatile (
        \\csrr a0, mcause
        \\csrr a1, mepc
        \\csrr a2, mtval
        \\csrr a3, mscratch
    );
    asm volatile (
        \\ld sp, 248(a3)
        \\call zig_rupt
    );

    // write return program counter from handler and get our trap frame back
    asm volatile (
        \\csrw mepc, a0
        \\csrr t6, mscratch
    );

    // restore all general purpose registers
    comptime var load_reg = 1;
    inline while (load_reg < 32) : (load_reg += 1) {
        @setEvalBranchQuota(10000);
        comptime var buf = [_]u8{0} ** 32;
        asm volatile (comptime std.fmt.bufPrint(
            &buf,
            "ld x{}, {}(t6)",
            .{ load_reg, (load_reg - 1) * 8 },
        ) catch unreachable);
    }

    asm volatile (
        \\mret
    );
    unreachable;
}

/// The actual interrupt vector above jumps here for high-level processing of the interrupt.
export fn zig_rupt(mcause: usize, epc: usize, tval: usize, frame: *TrapFrame) callconv(.C) usize {
    switch (@intToEnum(InterruptCause, mcause)) {
        .machine_timer => Timer.handle(),
        .machine_external => PLIC.handle(),
        else => |cause| unimplemented(cause, epc),
    }
    return epc;
}

/// Panic, AAAAAAAAAAAAAAAAAAAAAAAAA
pub fn unimplemented(cause: InterruptCause, mepc: usize) void {
    var buf = [_]u8{0} ** 128;
    @panic(std.fmt.bufPrint(
        buf[0..],
        "unhandled {} at 0x{x}",
        .{ cause, mepc },
    ) catch unreachable);
}
