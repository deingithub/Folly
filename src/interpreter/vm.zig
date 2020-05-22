//! This file is a deliberately minimal (read: effectively non-functional)
//! virtual machine that current pretends to be actual wasm processes so that
//! I can figure out the logic first and the wasm implementation details later.

const std = @import("std");
const heap = @import("../heap.zig");
const uart = @import("../uart.zig");

const example_tasks = @import("./example_tasks.zig");
const Frame = @import("./Frame.zig");

pub const VMNotifKind = @TagType(VMNotif);
pub const VMNotif = union(enum) {
    /// A new character from the UART is available.
    /// To handle, jump to handler and push data on the stack.
    uart_data: u8,
};

/// The task that should get the next compute cycle.
var active_task: *Frame.List.Node = undefined;
/// All tasks.
var tasks = Frame.List.init();
/// The last as of yet never used ID
var new_id: u32 = 0;

/// This just idles all the time.
var root_task = Frame.List.Node.init(.{
    .id = 0,
    .program = &[_]Frame.Instruction{},
    .waiting = true,
});

const debug = @import("build_options").log_vm;

pub fn init() void {
    if (comptime debug)
        uart.print("init interpreter...\n", .{});

    tasks.prepend(&root_task);
    active_task = &root_task;
    if (comptime debug)
        uart.print("  set up root idle task\n", .{});

    create_task(example_tasks.echo[0..]) catch @panic("Kernel OOM");
    create_task(example_tasks.just_think[0..]) catch @panic("Kernel OOM");
    create_task(example_tasks.did_you_know[0..]) catch @panic("Kernel OOM");
}

pub fn create_task(program: []const Frame.Instruction) !void {
    new_id += 1;
    errdefer new_id -= 1;

    const task = try tasks.createNode(.{
        .program = program,
        .id = new_id,
    }, &heap.kpagealloc);
    tasks.prepend(task);
}

pub fn notify(data: VMNotif) void {
    if (comptime debug)
        uart.print("notify: received {}\n", .{data});

    var it = tasks.first;
    while (it) |*node| : (it = node.*.next) {
        if (node.*.data.handlers[@enumToInt(data)]) |address| {
            if (comptime debug)
                uart.print("notify: adding to {}\n", .{node.*.data});

            node.*.data.notifs.append(data) catch @panic("Kernel OOM in virt.notify()");
            node.*.data.waiting = false;
        }
    }
}

pub fn switch_tasks() void {}

pub fn schedule() void {
    const my_debug = @import("build_options").log_sched;
    if (comptime my_debug)
        uart.print("schedule: rescheduling\n", .{});

    var next = active_task.next orelse tasks.first;
    if (next) |task| {
        if (!task.data.waiting) {
            if (comptime my_debug)
                uart.print("schedule: directly found non-waiting task id {}, switching\n", .{task.data.id});
            active_task = task;
            return;
        }
    }

    var it = tasks.first;
    while (it) |task| : (it = task.next) {
        if (!task.data.waiting) {
            if (comptime my_debug)
                uart.print("schedule: iteration found non-waiting task id {}, switching\n", .{task.data.id});
            active_task = task;
            return;
        }
    }

    if (comptime my_debug)
        uart.print("schedule: all tasks waiting, going to sleep\n", .{});
    asm volatile ("wfi");
    return;
}

pub fn run() void {
    while (true) {
        var me = active_task;
        var t = &me.data;
        // this shouldn't happen unless we return from a state where
        // all tasks were waiting
        if (t.waiting) {
            schedule();
            continue;
        }

        if (t.notifs.items.len > 0) {
            const notification = t.notifs.orderedRemove(0);
            t.stack[t.sp] = @intCast(u8, t.ip);
            t.sp += 1;
            switch (notification) {
                .uart_data => |char| {
                    t.stack[t.sp] = char;
                    t.sp += 1;
                },
            }
            t.ip = t.handlers[@enumToInt(notification)] orelse unreachable;
        }

        const inst = t.program[t.ip];
        defer {
            if (inst != .jump and inst != .jez) t.ip += 1;
        }

        if (comptime debug)
            uart.print("{}: executing {}\n", .{ t, t.program[t.ip] });

        switch (t.program[t.ip]) {
            .noop => {},
            .jump => {
                t.sp -= 1;
                t.ip = t.stack[t.sp];
            },
            .push_const => |val| {
                t.stack[t.sp] = val;
                t.sp += 1;
            },
            .push_const_vec => |val| {
                for (t.stack[t.sp .. t.sp + val.len]) |*b, i| b.* = val[i];
                t.sp += @intCast(u8, val.len);
            },
            .push_acc => {
                t.stack[t.sp] = t.acc;
                t.sp += 1;
            },
            .pop => {
                t.sp -= 1;
                t.acc = t.stack[t.sp];
            },
            .jez => {
                t.sp -= 1;
                const addr = t.stack[t.sp];
                if (t.acc == 0) {
                    t.ip = addr;
                } else {
                    t.ip += 1;
                }
            },
            .sub => {
                t.sp -= 2;
                t.acc = t.stack[t.sp] - t.stack[t.sp + 1];
            },
            .add => {
                t.sp -= 2;
                t.acc = t.stack[t.sp] + t.stack[t.sp + 1];
            },
            .yield => {
                schedule();
            },
            .exec => |command| {
                switch (command) {
                    .log => |len| {
                        t.sp -= len;
                        uart.print("task {}: {}\n", .{ t.id, t.stack[t.sp .. t.sp + len] });
                    },
                    .subscribe => |data| {
                        t.handlers[@enumToInt(data.kind)] = data.address;
                    },
                    .set_waiting => |val| {
                        t.waiting = val;
                    },
                }
            },
            .exit => {
                if (comptime debug)
                    uart.print("exited: {}\n", .{t});
                tasks.remove(me);
                tasks.destroyNode(me, &heap.kpagealloc);
                active_task = &root_task;
                schedule();
            },
        }
    }
}
