//! The UART serial console for printing messages. Yay.

const std = @import("std");
const Uart = @import("./mmio.zig").Uart;

/// Initialize the UART. Should be called very, *very* early. Must
/// have been called before any write/read occurs.
pub fn init() void {
    // Set word length
    Uart.lcr.write(u8, 0b0000_0011);
    Uart.fcr.write(u8, 0b0000_0001);
    // Enable received data interrupt
    Uart.ier.write(u8, 0b0000_0001);

    // Enable divisor latch
    Uart.lcr.write(u8, 0b1000_0011);

    // Set up signaling rate, values from http://osblog.stephenmarz.com/ch2.html
    const divisor: u16 = 592;

    // Write divisor halves
    const div_lower = @truncate(u8, divisor);
    Uart.base.write(u8, div_lower);
    const div_upper = @intCast(u8, divisor >> 8);
    Uart.ier.write(u8, div_upper);

    // Disable divisor latch
    Uart.lcr.write(u8, 0b0000_0011);

    print("init uart...\n", .{});
}

/// Formatted printing! Yay!
pub fn print(comptime format: []const u8, args: var) void {
    std.fmt.format(TermOutStream{ .context = {} }, format, args) catch unreachable;
}

// Boilerplate for using the stdlib's formatted printing
const TermOutStream = std.io.OutStream(void, error{}, termOutStreamWriteCallback);
fn termOutStreamWriteCallback(ctx: void, bytes: []const u8) error{}!usize {
    for (bytes) |byte| {
        put(byte);
    }
    return bytes.len;
}

/// Print a single character to the UART.
pub fn put(c: u8) void {
    Uart.base.write(u8, c);
}

/// Return a as of yet unread char or null.
fn read() ?u8 {
    if (Uart.lsr.read(u8) & 0b0000_0001 == 1) {
        return Uart.base.read(u8);
    } else {
        return null;
    }
}

/// This gets called by the PLIC handler in rupt/plic.zig
pub fn handle_interrupt() void {
    put(read().?);
}
