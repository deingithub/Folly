//! This file manages the CLINT timer interrupt

const std = @import("std");
const uart = @import("../uart.zig");

const virt = @import("../interpreter/vm.zig");
const mmio = @import("../mmio.zig");
const CLINT = mmio.CLINT;

/// How often to fire the timer interrupt [Hertz]
pub const frequency: usize = 40;
pub const clint_hertz: usize = 10_000_000;

pub fn init() void {
    CLINT.mtimecmp.write(
        usize,
        CLINT.mtime.read(usize) + clint_hertz / frequency,
    );
}

pub fn handle() void {
    CLINT.mtimecmp.write(
        usize,
        CLINT.mtime.read(usize) + clint_hertz / frequency,
    );
    virt.timer_reschedule();
}

pub fn uptime() usize {
    return CLINT.mtime.read(usize);
}

pub fn time() usize {
    return uptime() / frequency;
}

fn every(msecs: usize) bool {
    return uptime() % (frequency * msecs / 1000) == 0;
}
