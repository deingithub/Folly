//! This file is a deliberately minimal (read: effectively non-functional)
//! virtual machine that current pretends to be actual wasm processes so that
//! I can figure out the logic first and the wasm implementation details later.

const std = @import("std");
const heap = @import("../heap.zig");
const uart = @import("../uart.zig");

const assert = std.debug.assert;
const TaskList = std.SinglyLinkedList(Frame);

/// Contains all state a task needs to be executable
pub const Frame = struct {
    /// The VM's accumulator register
    acc: u8 = 0,
    /// The VM's instruction pointer
    ip: usize = 0,
    /// The program stack
    stack: [2048]u8 = [_]u8{0} ** 2048,
    /// The Stack Pointer points to the highest currently unused value on the stack
    sp: u11 = 0,
    /// The task's ID.
    id: u32,
    /// A list of instructions to execute
    program: []const Instruction,

    pub const Instruction = union(enum) {
        /// Don't.
        noop: void,
        /// Unconditionally jump to the argument index in the program.
        jump: usize,
        /// Die.
        exit: void,
        /// Push the argument onto the stack.
        push_const_vec: []const u8,
        /// Push the argument onto the stack.
        push_const: u8,
        /// Push the accumulator onto the stack.
        push_acc: void,
        /// Pop the last value from the stack into the accumulator.
        pop: void,
        /// Jump to the argument index in the program if accumulator is 0,
        /// otherwise no-op.
        jez: usize,
        /// Subtract the last value on the stack from the second-to-last value
        /// and put it into the accumulator.
        sub: void,
        /// Add the last and second-to-last value on the stack and put it into
        /// the accumulator.
        add: void,
        /// Call a non-trivial kernel-provided function. See individual
        /// enum members for details.
        exec: union(enum) {
            /// Pop <arg> bytes from the stack and write them to UART. Do not
            /// assume any particular formatting.
            log: u11,
            /// Let the scheduler know that there's nothing to do right now.
            /// Execution will resume after an indeterminate amount of time.
            yield: void,
        },
    };
};

comptime {
    assert(@sizeOf(TaskList.Node) <= heap.page_size);
}

/// The task that should get the next compute cycle.
var active_task: *TaskList.Node = undefined;
/// All tasks.
var tasks = TaskList.init();
/// The last as of yet never used ID
var new_id: u32 = 0;

/// This just idles all the time.
var root_task = TaskList.Node.init(.{
    .id = 0,
    .program = &[_]Frame.Instruction{
        .{ .exec = .{ .yield = {} } },
        .{ .jump = 0 },
    },
});

const ex_1_string = "Did you know that world-renowned writer Stephen King was once hit by a car?";
pub const ex_1 = [_]Frame.Instruction{
    .{ .push_const_vec = ex_1_string },
    .{ .push_const = 3 },
    .{ .pop = {} },
    .{ .push_acc = {} },
    .{ .push_const = 1 },
    .{ .sub = {} },
    .{ .exec = .{ .log = ex_1_string.len } },
    .{ .jez = 11 },
    .{ .exec = .{ .yield = {} } },
    .{ .push_const_vec = ex_1_string },
    .{ .jump = 3 },
    .{ .exit = {} },
};

const ex_2_string = "Just something to consider.";
pub const ex_2 = [_]Frame.Instruction{
    .{ .push_const_vec = ex_2_string },
    .{ .push_const = 3 },
    .{ .pop = {} },
    .{ .push_acc = {} },
    .{ .push_const = 1 },
    .{ .sub = {} },
    .{ .exec = .{ .log = ex_2_string.len } },
    .{ .jez = 11 },
    .{ .push_const_vec = ex_2_string },
    .{ .exec = .{ .yield = {} } },
    .{ .jump = 3 },
    .{ .exit = {} },
};

/// whether or not to spam debug information to UART in methods
const debug = false;

pub fn init() void {
    uart.print("init interpreter...\n", .{});
    tasks.prepend(&root_task);
    active_task = &root_task;
    uart.print("  set up root idle task\n", .{});

    create_task(ex_2[0..]) catch @panic("Kernel OOM");
    create_task(ex_1[0..]) catch @panic("Kernel OOM");
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

pub fn rupt() void {
    if (comptime debug)
        uart.print("hit interrupt.\n", .{});
    reschedule(active_task.next);
}

fn reschedule(next: ?*TaskList.Node) void {
    if (comptime debug)
        uart.print("rescheduling.\n", .{});
    active_task = next orelse tasks.first orelse @panic("can't reschedule, no tasks");
}

pub fn run() void {
    while (true) {
        var t = &active_task.data;
        const inst = t.program[t.ip];
        defer {
            if (inst != .jump and inst != .jez) t.ip += 1;
        }

        if (comptime debug) uart.print("executing {} in {}\n", .{ t.program[t.ip], t });

        switch (t.program[t.ip]) {
            .noop => {},
            .jump => |addr| {
                t.ip = addr;
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
            .jez => |addr| {
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
            .exec => |command| {
                switch (command) {
                    .log => |len| {
                        t.sp -= len;
                        uart.print("task {}: {}\n", .{ t.id, t.stack[t.sp .. t.sp + len] });
                    },
                    .yield => {
                        reschedule(active_task.next);
                    },
                }
            },
            .exit => {
                if (comptime debug)
                    uart.print("exited: id {} {}\n", .{ t.id, t });
                const next = active_task.next;
                tasks.remove(active_task);
                tasks.destroyNode(active_task, &heap.kpagealloc);
                reschedule(next);
            },
        }
    }
}
