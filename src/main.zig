const std = @import("std");
const builtin = @import("builtin");

const uart = @import("./uart.zig");
const heap = @import("./heap.zig");
const rupt = @import("./rupt.zig");

comptime {
    // startup code, I can't be bothered to modify build.zig for this
    asm (@embedFile("./startup.asm"));
}

// this gets called by the startup code. we are in machine mode.
export fn kmain() noreturn {
    uart.init();
    heap.init();
    rupt.init();

    uart.print("init kmain...\n\n", .{});

    var kalloc = std.heap.FixedBufferAllocator.init(
        heap.alloc_pages(1024) catch @panic("Kernel OOM"),
    );

    var things = std.StringHashMap(usize).init(&kalloc.allocator);
    things.putNoClobber("answer", 42) catch unreachable;
    uart.print("the answer is: {}\n", .{things.get("answer")});

    asm volatile ("j youspinmeround");
    unreachable;
}

// Invoked in a lot of cases and @panic, courtesy of zig.
// TODO implement stacktraces: https://andrewkelley.me/post/zig-stack-traces-kernel-panic-bare-bones-os.html
pub fn panic(msg: []const u8, error_return_trace: ?*builtin.StackTrace) noreturn {
    @setCold(true);
    uart.print("Kernel Panic: {}\nIt's now safe to turn off your computer.\n", .{msg});
    while (true) {}
}
