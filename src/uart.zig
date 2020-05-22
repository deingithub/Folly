//! The UART serial console for printing messages. Yay.

const std = @import("std");
const Uart = @import("./mmio.zig").Uart;
const virt = @import("./interpreter/vm.zig");

const debug = @import("build_options").log_uart;

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

    if (comptime debug)
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

/// Shamelessly stolen from Wikipedia, useful ANSI sequences
pub const ANSIFormat = struct {
    pub const CSI = "\x1b[";
    pub const SGR = struct {
        pub const reset = CSI ++ "0m";
        pub const bold = CSI ++ "1m";
        pub const italic = CSI ++ "3m";
        pub const underline = CSI ++ "4m";

        pub const set_fg = CSI ++ "38;5;";
        pub const set_bg = CSI ++ "48;5;";
        pub const Color = enum {
            black,
            red,
            green,
            yellow,
            blue,
            magenta,
            cyan,
            white,

            pub const Black = "0m";
            pub const Red = "1m";
            pub const Green = "2m";
            pub const Yellow = "3m";
            pub const Blue = "4m";
            pub const Magenta = "5m";
            pub const Cyan = "6m";
            pub const White = "7m";

            pub fn string(self: Color) []const u8 {
                return switch (self) {
                    .black => Black,
                    .red => Red,
                    .green => Green,
                    .yellow => Yellow,
                    .blue => Blue,
                    .magenta => Magenta,
                    .cyan => Cyan,
                    .white => White,
                };
            }
        };

        // this is currently bugged. I think so, at least. TODO figure it out
        // pub const RenderOpts = struct {
        //     bold: bool = false,
        //     italic: bool = false,
        //     underline: bool = false,
        //     fg: ?SGR.Color = null,
        //     bg: ?SGR.Color = null,
        // };
        // pub fn render(comptime str: []const u8, comptime opts: RenderOpts) []const u8 {
        //     comptime var buf = [_]u8{0} ** (str.len + 64);
        //     const fmt_bold = if (opts.bold) bold else "";
        //     const fmt_italic = if (opts.italic) italic else "";
        //     const fmt_underline = if (opts.underline) underline else "";
        //     const fmt_fg = if (opts.fg) |color| set_fg ++ color.string() else "";
        //     const fmt_bg = if (opts.bg) |color| set_bg ++ color.string() else "";

        //     return comptime std.fmt.bufPrint(
        //         &buf,
        //         "{}{}{}{}{}{}{}",
        //         .{ fmt_bold, fmt_italic, fmt_underline, fmt_fg, fmt_bg, str, reset },
        //     ) catch unreachable;
        // }
    };
};
/// This gets called by the PLIC handler in rupt/plic.zig
pub fn handle_interrupt() void {
    const char = read().?;
    virt.notify(.{ .uart_data = char });
    // switch (char) {
    //     // what enter sends
    //     '\r' => {
    //         put('\n');
    //     },
    //     // technically the first one is backspace but everyone uses the second one instead
    //     '\x08', '\x7f' => {
    //         put('\x08');
    //         put(' ');
    //         put('\x08');
    //     },
    //     else => put(char),
    // }
}
