//! This file has a low-level interface into the PLIC received interrupts.

const std = @import("std");

const uart = @import("../uart.zig");
const mmio = @import("../mmio.zig");
const PLIC = mmio.PLIC;

/// Enable these interrupts with these priorities.
const interrupts = [_]struct { id: u6, priority: u3 }{
    // The UART's Data Received interrupt.
    .{ .id = 10, .priority = 6 },
};

/// Initialize the PLIC, setting up which interrupts to receive etc.
pub fn init() void {
    for (interrupts) |interrupt| {
        PLIC.enable.write(
            usize,
            PLIC.enable.read(usize) | @as(usize, 0b1) << interrupt.id,
        );
        PLIC.priority.write_offset(
            u3,
            4 * interrupt.id,
            interrupt.priority,
        );
    }
    PLIC.threshold.write(u8, 1);
}

/// Fetches the id of the device that caused the interrupt.
fn claim() ?u6 {
    const id = PLIC.claim_or_complete.read(u6);
    return if (id == 0) null else id;
}

/// Marks the most recent interrupt of the id as completed.
fn complete(id: u6) void {
    PLIC.claim_or_complete.write(u6, id);
}

pub fn handle() void {
    const id = claim().?;

    switch (id) {
        10 => uart.handle_interrupt(),
        else => {
            var buf = [_]u8{0} ** 128;
            var msg = std.fmt.bufPrint(
                buf[0..],
                "unhandled PLIC interrupt, source {}",
                .{id},
            ) catch unreachable;
            @panic(msg);
        },
    }
    complete(id);
}
