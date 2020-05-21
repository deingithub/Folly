//! This file contains the top level interrupt handler

const std = @import("std");

const uart = @import("./uart.zig");
const heap = @import("./heap.zig");
pub const Timer = @import("./rupt/timer.zig");
pub const PLIC = @import("./rupt/plic.zig");

/// Initialize all necessary values. Must be called as early as possible
/// after UART is available.
pub fn init() void {
    const k_trap_stack = heap.alloc_pages(1) catch @panic("Kernel OOM while trying to allocate kernel trap stack in rupt.init()");
    kframe.trap_stack = &(k_trap_stack[k_trap_stack.len - 1]);
    uart.print("init interrupts...\n", .{});
    Timer.init();
    uart.print("  timer interrupt at {}Hz\n", .{Timer.frequency});
    PLIC.init();
    uart.print("  PLIC enabled\n", .{});
}

const TrapFrame = extern struct {
    regs: [32]usize, // byte 0-255
    trap_stack: *u8, // byte 256-263
    hartid: usize, // byte 264-271
};

export var kframe linksection(".bss") = TrapFrame{
    .regs = [_]usize{0} ** 32,
    .trap_stack = undefined,
    .hartid = 0,
};

fn async_interrupt(comptime n: u63) u64 {
    return (1 << 63) + @as(usize, n);
}
fn sync_interrupt(comptime n: u63) u64 {
    return (0 << 63) + @as(usize, n);
}

/// This *ought* to be a non-exhaustive enum because the spec allows
/// implementation-defined interrupts, but why would I bother with that.
pub const InterruptCause = enum(u64) {
    // Asynchronous Interrupts
    user_software = async_interrupt(0),
    supervisor_software = async_interrupt(1),
    // async_interrupt(2) reserved
    machine_software = async_interrupt(3),
    user_timer = async_interrupt(4),
    supervisor_timer = async_interrupt(5),
    // async_interrupt(6) reserved
    machine_timer = async_interrupt(7),
    user_external = async_interrupt(8),
    supervisor_external = async_interrupt(9),
    // async_interrupt(10) reserved
    machine_external = async_interrupt(11),
    // Synchronous Interrupts
    instruction_address_misaligned = sync_interrupt(0),
    instruction_access_faul = sync_interrupt(1),
    illegal_instruction = sync_interrupt(2),
    breakpoint = sync_interrupt(3),
    load_address_misaligned = sync_interrupt(4),
    load_access_fault = sync_interrupt(5),
    store_amo_address_misaligned = sync_interrupt(6),
    store_amo_access_fault = sync_interrupt(7),
    environment_call_from_user = sync_interrupt(8),
    environment_call_from_supervisor = sync_interrupt(9),
    // sync_interrupt(10) reserved
    environment_call_from_machine = sync_interrupt(11),
    instruction_page_fault = sync_interrupt(12),
    load_page_fault = sync_interrupt(13),
    // sync_interrupt(14) reserved
    store_amo_page_fault = sync_interrupt(15),
};

/// The interrupt vector that the processor jumps to
export fn rupt() align(4) callconv(.Naked) void {
    comptime {
        std.debug.assert(@sizeOf(TrapFrame) == 272); // when this fails, adjust the code below!
    }

    // atomically swap trap frame address into t6
    asm volatile ("csrrw t6, mscratch, t6");

    // save first 31 general purpose registers into the trap frame
    comptime var save_reg = 0;
    inline while (save_reg < 31) : (save_reg += 1) {
        @setEvalBranchQuota(5700);
        comptime var buf = [_]u8{0} ** 32;
        asm volatile (comptime std.fmt.bufPrint(
            &buf,
            "sd x{}, {}(t6)",
            .{ save_reg, save_reg * 8 },
        ) catch unreachable);
    }
    // save register x31
    asm volatile (
        \\mv t5, t6
        \\sd t6, 31*8(t5)
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
        \\ld sp, 256(a3)
        \\call zig_rupt
    );

    // write return program counter from handler and get our trap frame back
    asm volatile (
        \\csrw mepc, a0
        \\csrr t6, mscratch
    );

    // restore all general purpose registers
    comptime var load_reg = 0;
    inline while (load_reg < 32) : (load_reg += 1) {
        @setEvalBranchQuota(10800);
        comptime var buf = [_]u8{0} ** 32;
        asm volatile (comptime std.fmt.bufPrint(
            &buf,
            "ld x{}, {}(t6)",
            .{ load_reg, load_reg * 8 },
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
