//! This represents a line in the process of being entered by the user.
//! To use, invoke read(char) every time you get a new character. It returns
//! null or a complete line. It will automatically provide line editing
//! functionality; don't use the UART while it's being used.

const std = @import("std");
const uart = @import("../uart.zig");
const Self = @This();

buffer: std.ArrayList(u8),
done: bool,

pub fn init(allocator: *std.mem.Allocator) Self {
    return .{
        .buffer = std.ArrayList(u8).init(allocator),
        .done = false,
    };
}

pub fn deinit(self: *Self) void {
    self.buffer.deinit();
    self.* = undefined;
}

pub fn get(self: *Self) ?[]const u8 {
    if (self.done) {
        return self.buffer.items;
    } else {
        return null;
    }
}

pub fn read(self: *Self, ch: u8) !?[]const u8 {
    var should_render = true;
    defer if (should_render) self.renderChar(ch);
    switch (ch) {
        '\r' => {
            self.done = true;
            return self.buffer.items;
        },
        '\x08', '\x7f' => {
            if (self.buffer.items.len > 0) {
                _ = self.buffer.orderedRemove(self.buffer.items.len - 1);
            } else {
                uart.put('\x07'); // Bell
                should_render = false;
            }
            return null;
        },
        else => {
            try self.buffer.append(ch);
            return null;
        },
    }
}

fn renderChar(self: *Self, ch: u8) void {
    switch (ch) {
        // what enter sends
        '\r' => {
            uart.put('\n');
        },
        // technically the first one is backspace but everyone uses the second one instead
        '\x08', '\x7f' => {
            uart.put('\x08');
            uart.put(' ');
            uart.put('\x08');
        },
        else => uart.put(ch),
    }
}
