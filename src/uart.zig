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

/// A stack for temporarily storing things that look like escape sequences
var input_stack = [_]u8{0} ** 8;
var input_stack_top: u8 = 0;

/// What we're doing currently.
var state: enum {
    passthru,
    seen_escape,
    task_switching,
} = .passthru;

/// This gets called by the PLIC handler in rupt/plic.zig
pub fn handle_interrupt() void {
    const eql = std.mem.eql;

    const char = read().?;

    if (char == '\x1b')
        state = .seen_escape;

    switch (state) {
        .passthru => virt.notify(.{ .uart_data = char }),
        .seen_escape => {
            if (comptime debug)
                print("uart: seen escape, this char is {x}\n", .{char});

            var maybe_found = false;
            input_stack[input_stack_top] = char;
            input_stack_top += 1;

            for (known_escapes) |seq| {
                if (input_stack_top > seq.len) continue;
                if (std.mem.eql(u8, seq[0..input_stack_top], input_stack[0..input_stack_top])) {
                    maybe_found = true;
                    if (seq.len == input_stack_top) {
                        handle_escape_sequence(input_stack[0..input_stack_top]);
                    }
                    break;
                }
            }

            if (!maybe_found) {
                if (comptime debug)
                    print("uart: this couldn't possibly be a known escape\n", .{});
                for (input_stack[0..input_stack_top]) |ch| virt.notify(.{ .uart_data = ch });
                input_stack_top = 0;
            }
        },
        .task_switching => {},
    }
}

/// What to do when we find any escape sequence. Called by handle_interrupt.
fn handle_escape_sequence(data: []const u8) void {
    switch (explain_escape_sequence(data).?) {
        .F1 => {
            print("woo yeah it's a fucking task switcher\n", .{});
        },
        .F9 => {
            @panic("you have no one to blame but yourself");
        },
    }
    input_stack_top = 0;
    state = .passthru;
}

/// All escape sequence variants we care about
const known_escapes = [_][]const u8{
    "\x1bOP", "\x1b[11~", "\x1bOw", "\x1b[20~",
};
/// Turns out there are more than one representation for some sequences. Yay.
/// This function takes a slice and checks if it is one that we care about,
/// returning a self-descriptive enum variant or null if it just isn't.
fn explain_escape_sequence(data: []const u8) ?enum { F1, F9 } {
    const eql = std.mem.eql;
    if (eql(u8, data, "\x1bOP") or eql(u8, data, "\x1b[11~")) {
        return .F1;
    } else if (eql(u8, data, "\x1bOw") or eql(u8, data, "\x1b[20~")) {
        return .F9;
    }

    return null;
}
