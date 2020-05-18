//! This file manages the CLINT timer interrupt

const std = @import("std");

const mmio = @import("../mmio.zig");
const CLINT = mmio.CLINT;

/// Uptime in timer cycles
var uptime: usize = 0;

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
    uptime += 1;

    CLINT.mtimecmp.write(
        usize,
        CLINT.mtime.read(usize) + clint_hertz / frequency,
    );
}

pub fn time() usize {
    return uptime / frequency;
}

fn every(secs: usize) bool {
    return uptime % (frequency * secs) == 0;
}
