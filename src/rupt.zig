//! This file contains the top level interrupt handler

const std = @import("std");

const uart = @import("./uart.zig");
pub const Timer = @import("./rupt/timer.zig");
pub const PLIC = @import("./rupt/plic.zig");

/// Initialize all necessary values. Must be called as early as possible
/// after UART is available.
pub fn init() void {
    uart.print("init interrupts...\n", .{});
    Timer.init();
    uart.print("  timer interrupt at {}Hz\n", .{Timer.frequency});
    PLIC.init();
    uart.print("  PLIC enabled\n", .{});
}

/// The assembly interrupt vector jumps here.
pub fn handle(mcause: usize, mepc: usize) callconv(.C) void {
    const is_async = @clz(usize, mcause) == 0;

    if (is_async) {
        switch (@truncate(u63, mcause)) {
            7 => Timer.handle(),
            11 => PLIC.handle(),
            else => unimplemented(mcause, mepc),
        }
    } else {
        switch (@truncate(u63, mcause)) {
            else => unimplemented(mcause, mepc),
        }
    }
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
