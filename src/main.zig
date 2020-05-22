const std = @import("std");
const builtin = @import("builtin");

const uart = @import("./uart.zig");
const heap = @import("./heap.zig");
const rupt = @import("./rupt.zig");
const virt = @import("/interpreter/vm.zig");
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
    virt.init();

    const SGR = uart.ANSIFormat.SGR;
    uart.print(
        \\Welcome to {}The Folly of Cass{}.
        \\{}[F1]{} to switch tasks
        \\{}[F9]{} to shut down
        \\
        \\Godspeed.
        \\
    , .{
        SGR.set_fg ++ SGR.Color.Yellow, SGR.reset, SGR.bold, SGR.reset, SGR.bold, SGR.reset,
    });

    if (options.log_vm)
        uart.print("  handover to interpreter...\n", .{});

    virt.run();

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
