//! This file contains the top level interrupt handler

const std = @import("std");

const uart = @import("./uart.zig");
const heap = @import("./heap.zig");
pub const Timer = @import("./rupt/timer.zig");
pub const PLIC = @import("./rupt/plic.zig");

comptime {
    std.debug.assert(@sizeOf(TrapFrame) == 272);
    asm (@embedFile("./rupt.asm"));
}

/// Initialize all necessary values. Must be called as early as possible
/// after UART is available.
pub fn init() void {
    const k_trap_stack = heap.alloc_pages(1) catch @panic("Kernel OOM");
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

/// The assembly interrupt vector jumps here.
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
    const panic = std.fmt.bufPrint(
        buf[0..],
        "unhandled {} interrupt #{} at 0x{x}",
        .{
            fmt_kind,
            cause,
            mepc,
        },
    ) catch unreachable;

    @panic(panic);
}
