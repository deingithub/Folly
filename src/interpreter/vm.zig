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
    /// Pending Notifications
    notifs: std.ArrayList(VMNotif) = std.ArrayList(VMNotif).init(&heap.kpagealloc),
    /// Handler addresses for notifications
    handlers: [@typeInfo(VMNotifKind).Enum.fields.len]?usize = [_]?usize{null} ** @typeInfo(VMNotifKind).Enum.fields.len,

    pub const Instruction = union(enum) {
        /// Don't.
        noop: void,
        /// Pop an index from the stack and unconditionally jump there.
        jump: void,
        /// Die.
        exit: void,
        /// Push the argument onto the stack.
        push_const_vec: []const u8,
        /// Push the argument onto the stack.
        push_const: u8,
        /// Push the accumulator onto the stack.
        push_acc: void,
        /// Pop a value from the stack into the accumulator.
        pop: void,
        /// Pop an index from the stack and jump there if accumulator is 0,
        /// otherwise no-op.
        jez: void,
        /// Subtract the last value on the stack from the second-to-last value
        /// and put it into the accumulator.
        sub: void,
        /// Add the last and second-to-last value on the stack and put it into
        /// the accumulator.
        add: void,
        /// Let the scheduler know that there's nothing to do right now.
        /// Execution will resume after an indeterminate amount of time.
        yield: void,
        /// Call a non-trivial kernel-provided function. See individual
        /// enum members for details.
        exec: union(enum) {
            /// Pop <arg> bytes from the stack and write them to UART. Do not
            /// assume any particular formatting.
            log: u11,
            /// Set up a specific address in the program to be jumped to in
            /// case a specific notification is issued to the VM. The current
            /// instruction pointer will be pushed onto the stack. Return using
            /// jump.
            subscribe: struct { address: usize, kind: VMNotifKind },
        },
    };

    pub fn format(t: Frame, comptime fmt: []const u8, options: std.fmt.FormatOptions, out_stream: var) !void {
        const val = if (t.sp == 0) -1 else @as(i16, t.stack[t.sp - 1]);
        try std.fmt.format(out_stream, "Task(id = {}, ip = {}, sp = {}, acc = {}, [sp-1] = {})", .{ t.id, t.ip, t.sp, t.acc, val });
    }
};

comptime {
    assert(@sizeOf(TaskList.Node) <= heap.page_size); // come on it didn't have to be that big
}

pub const VMNotifKind = @TagType(VMNotif);
pub const VMNotif = union(enum) {
    /// A new character from the UART is available.
    /// To handle, jump to handler and push data on the stack.
    uart_data: u8,
};

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
        .{ .yield = {} },
        .{ .push_const = 0 },
        .{ .jump = {} },
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
    .{ .push_const = 13 },
    .{ .jez = {} },
    .{ .yield = {} },
    .{ .push_const_vec = ex_1_string },
    .{ .push_const = 3 },
    .{ .jump = {} },
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
    .{ .push_const = 13 },
    .{ .jez = {} },
    .{ .push_const_vec = ex_2_string },
    .{ .yield = {} },
    .{ .push_const = 3 },
    .{ .jump = {} },
    .{ .exit = {} },
};

pub const echo = [_]Frame.Instruction{
    .{ .exec = .{ .subscribe = .{ .kind = .uart_data, .address = 4 } } },
    .{ .yield = {} },
    .{ .push_const = 1 },
    .{ .jump = {} },
    .{ .exec = .{ .log = 1 } },
    .{ .jump = {} },
};

/// whether or not to spam debug information to UART in methods
const debug = false;

pub fn init() void {
    uart.print("init interpreter...\n", .{});
    tasks.prepend(&root_task);
    active_task = &root_task;
    uart.print("  set up root idle task\n", .{});
    create_task(echo[0..]) catch @panic("Kernel OOM");

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

pub fn notify(data: VMNotif) void {
    if (comptime debug)
        uart.print("hit interrupt.\n", .{});
    var it = tasks.first;
    while (it) |*node| : (it = node.*.next) {
        if (node.*.data.handlers[@enumToInt(data)]) |address| {
            node.*.data.notifs.append(data) catch @panic("Kernel OOM in virt.notify()");
        }
    }
}

pub fn timer_reschedule() void {
    reschedule(active_task.next);
}

fn reschedule(next: ?*TaskList.Node) void {
    if (comptime debug)
        uart.print("rescheduling.\n", .{});
    active_task = next orelse tasks.first orelse &root_task;
}

pub fn run() void {
    while (true) {
        var t = &active_task.data;

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

        if (comptime debug and t.id != 0) uart.print("{}: executing {}\n", .{ t, t.program[t.ip] });

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
                reschedule(active_task.next);
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
