const std = @import("std");
const builtin = @import("builtin");

const uart = @import("./uart.zig");
const heap = @import("./heap.zig");
const rupt = @import("./rupt.zig");
const interpreter = @import("./interpreter.zig");
const options = @import("build_options");

comptime {
    // startup code, I can't be bothered to modify build.zig for this
    asm (@embedFile("./startup.asm"));
}

// this gets called by the startup code. we are in machine mode.
export fn kmain() noreturn {
    uart.init();
    heap.init();
    rupt.init();
    interpreter.init();

    const SGR = uart.ANSIFormat.SGR;
    uart.print(
        \\Welcome to {}.
        \\{} to switch tasks
        \\{} to shut down
        \\
        \\Godspeed.
        \\
    , .{
        SGR.render("The Folly of Cass", SGR.RenderOpts{ .fg = .yellow }),
        SGR.render("[F1]", SGR.RenderOpts{ .bold = true }),
        SGR.render("[F9]", SGR.RenderOpts{ .bold = true }),
    });

    if (options.log_vm) uart.print("handover to interpreter...\n", .{});
    interpreter.run();

    asm volatile ("j youspinmeround");
    unreachable;
}

// Invoked in a lot of cases and @panic, courtesy of zig.
// TODO implement stacktraces: https://andrewkelley.me/post/zig-stack-traces-kernel-panic-bare-bones-os.html
pub fn panic(msg: []const u8, error_return_trace: ?*builtin.StackTrace) noreturn {
    @setCold(true);
    uart.print("Kernel Panic: {}\nIt's now safe to turn off your computer.\n", .{msg});
    asm volatile (
        \\csrw mie, zero
        \\j youspinmeround
    );
    unreachable;
}
