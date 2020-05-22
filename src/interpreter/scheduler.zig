const interpreter = @import("../interpreter.zig");
const uart = @import("../uart.zig");

pub fn schedule() void {
    const my_debug = @import("build_options").log_sched;
    if (comptime my_debug)
        uart.print("schedule: rescheduling\n", .{});

    var next = interpreter.active_task.next orelse interpreter.tasks.first;
    if (next) |task| {
        if (!task.data.waiting) {
            if (comptime my_debug)
                uart.print("schedule: directly found non-waiting task id {}, switching\n", .{task.data.id});
            interpreter.active_task = task;
            return;
        }
    }

    var it = interpreter.tasks.first;
    while (it) |task| : (it = task.next) {
        if (!task.data.waiting) {
            if (comptime my_debug)
                uart.print("schedule: iteration found non-waiting task id {}, switching\n", .{task.data.id});
            interpreter.active_task = task;
            return;
        }
    }

    if (comptime my_debug)
        uart.print("schedule: all tasks waiting, going to sleep\n", .{});
    asm volatile ("wfi");
    return;
}
