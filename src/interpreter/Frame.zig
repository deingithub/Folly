//! Contains all state a task needs to be executable

const std = @import("std");
const assert = std.debug.assert;

const heap = @import("../heap.zig");
const virt = @import("./vm.zig");

pub const List = std.SinglyLinkedList(@This());

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
notifs: std.ArrayList(virt.VMNotif) = std.ArrayList(virt.VMNotif).init(&heap.kpagealloc),
/// Handler addresses for notifications
handlers: [@typeInfo(virt.VMNotifKind).Enum.fields.len]?usize = [_]?usize{null} ** @typeInfo(virt.VMNotifKind).Enum.fields.len,
/// Whether or not the task is doing nothing but waiting for a notification to happen
waiting: bool = false,

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
        subscribe: struct { address: usize, kind: virt.VMNotifKind },
        /// Set the task's waiting status. Waiting tasks will only be
        /// resumed when a notification they have subscribed to
        /// is generated, after which set_waiting has to be issued again.
        set_waiting: bool,
    },
};

pub fn format(t: Frame, comptime fmt: []const u8, options: std.fmt.FormatOptions, out_stream: var) !void {
    const val = if (t.sp == 0) -1 else @as(i16, t.stack[t.sp - 1]);
    try std.fmt.format(out_stream, "Task(id = {}, ip = {}, sp = {}, acc = {}, [sp-1] = {})", .{ t.id, t.ip, t.sp, t.acc, val });
}

comptime {
    assert(@sizeOf(List.Node) <= heap.page_size); // come on it didn't have to be that big
}
