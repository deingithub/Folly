//! This file has a low-level interface into the PLIC received interrupts.
//! Relevant qemu source:
//! https://git.qemu.org/?p=qemu.git;a=blob;f=include/hw/riscv/virt.h;h=e69355efafad3b32d3ac90a988dafe64ba27f9e2;hb=HEAD

const std = @import("std");

const uart = @import("../uart.zig");
const mmio = @import("../mmio.zig");
const PLIC = mmio.PLIC;

const debug = @import("build_options").log_plic;

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
        PLIC.priority.writeOffset(
            u3,
            4 * interrupt.id,
            interrupt.priority,
        );
    }
    PLIC.threshold.write(u8, 1);
    if (comptime debug)
        uart.print("  PLIC set up\n", .{});
}

/// Fetches the id of the device that caused the interrupt.
fn claim() ?u7 {
    const id = PLIC.claim_or_complete.read(u7);
    return if (id == 0) null else id;
}

/// Marks the most recent interrupt of the id as completed.
fn complete(id: u7) void {
    PLIC.claim_or_complete.write(u7, id);
}

pub fn handle() void {
    const id = claim().?;

    switch (id) {
        10 => uart.handleInterrupt(),
        else => {
            var buf = [_]u8{0} ** 128;

            @panic(std.fmt.bufPrint(
                buf[0..],
                "unhandled PLIC interrupt, source {}",
                .{id},
            ) catch unreachable);
        },
    }
    complete(id);
}
