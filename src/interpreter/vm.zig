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
        },
    };
};

/// The task that should get the next compute cycle.
var active_task: *TaskList.Node = undefined;
/// All tasks.
var tasks = TaskList.init();
/// The last as of yet never used ID
var new_id: u32 = 0;

const example_string = "Did you know that world-renowned writer Stephen King was once hit by a car?";

pub const root_task = [_]Frame.Instruction{
    .{ .push_const_vec = example_string },
    .{ .push_const = 3 },
    .{ .pop = {} },
    .{ .push_acc = {} },
    .{ .push_const = 1 },
    .{ .sub = {} },
    .{ .exec = .{ .log = example_string.len } },
    .{ .jez = 10 },
    .{ .push_const_vec = example_string },
    .{ .jump = 3 },
    .{ .exit = {} },
};

/// whether or not to spam debug information to UART in methods
const debug = false;

pub fn init() void {
    uart.print("init interpreter...\n", .{});
    create_task(root_task[0..]) catch @panic("Kernel OOM while trying to create root task in vm.init()");
    active_task = tasks.first.?;
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

comptime {
    assert(@sizeOf(TaskList.Node) <= heap.page_size);
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
                }
            },
            .exit => {
                if (comptime debug)
                    uart.print("exited: id {} {}\n", .{ t.id, t });
                asm volatile ("j youspinmeround");
            },
        }
    }
}
