//! This file manages all memory-mapped IO with a fancy set of helpers.

const std = @import("std");
const assert = std.debug.assert;

/// A mixin usable with `pub usingnamespace MMIO(@This())` on any enum(usize).
/// Adds IO functions for interacting with MMIO addresses defined in the enum members.
fn MMIO(comptime T: type) type {
    return struct {
        pub fn write(self: T, comptime U: type, data: U) void {
            write_offset(self, U, 0, data);
        }
        pub fn read(self: T, comptime U: type) U {
            return read_offset(self, U, 0);
        }

        pub fn write_offset(self: T, comptime U: type, offset: usize, data: U) void {
            comptime assert(@typeInfo(U) == .Int);
            const ptr = @intToPtr([*]volatile U, @enumToInt(self));
            ptr[offset] = data;
        }
        pub fn read_offset(self: T, comptime U: type, offset: usize) U {
            comptime assert(@typeInfo(U) == .Int);
            const ptr = @intToPtr([*]volatile U, @enumToInt(self));
            return ptr[offset];
        }
    };
}

/// MMIO addresses for the UART.
pub const Uart = enum(usize) {
    /// Base address, write/read data
    base = 0x1000_0000,
    /// Interrupt Enable Register
    ier = 0x1000_0001,
    /// FIFO Control Register
    fcr = 0x1000_0002,
    /// Line Control Register
    lcr = 0x1000_0003,
    // Line Status Register
    lsr = 0x1000_0005,

    pub usingnamespace MMIO(@This());
};

/// MMIO adresses for the Core Local Interrupter.
pub const CLINT = enum(usize) {
    mtimecmp = 0x0200_4000,
    mtime = 0x0200_bff8,

    pub usingnamespace MMIO(@This());
};

/// MMIO addresses for the Platform Level Interrupt Controller.
pub const PLIC = enum(usize) {
    /// Sets the priority of a particular interrupt source
    priority = 0x0c00_0000,
    /// Contains a list of interrupts that have been triggered (are pending)
    pending = 0x0c00_1000,
    /// Enable/disable certain interrupt sources
    enable = 0x0c00_2000,
    /// Sets the threshold that interrupts must meet before being able to trigger.
    threshold = 0x0c20_0000,
    /// Returns the next interrupt in priority order or completes handling of a particular interrupt.
    claim_or_complete = 0x0c20_0004,

    pub usingnamespace MMIO(@This());
};
