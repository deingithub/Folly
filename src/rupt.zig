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
export fn zig_rupt(cause: usize, epc: usize, tval: usize, frame: *TrapFrame) callconv(.C) usize {
    const is_async = @clz(usize, cause) == 0;

    if (is_async) {
        switch (@truncate(u63, cause)) {
            7 => Timer.handle(),
            11 => PLIC.handle(),
            else => unimplemented(cause, epc),
        }
    } else {
        switch (@truncate(u63, cause)) {
            else => unimplemented(cause, epc),
        }
    }

    return epc;
}

/// Panic, AAAAAAAAAAAAAAAAAAAAAAAAA
pub fn unimplemented(mcause: usize, mepc: usize) void {
    const is_async = @clz(usize, mcause) == 0;
    const cause = @truncate(u63, mcause);

    var buf = [_]u8{0} ** 128;
    const fmt_kind = if (is_async) "async" else "sync";

    @panic(std.fmt.bufPrint(
        buf[0..],
        "unhandled {} interrupt #{} at 0x{x}",
        .{
            fmt_kind,
            cause,
            mepc,
        },
    ) catch unreachable);
}
