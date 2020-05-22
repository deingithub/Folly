//! This is the main VM file, providing high level access to running tasks.
//! The grubby details are elsewhere in src/interpreter/.

pub const heap = @import("./heap.zig");
pub const vm = @import("./interpreter/vm.zig");
pub const Frame = @import("./interpreter/Frame.zig");
pub const schedule = scheduler.schedule;
pub const notify = notification.notify;

const notification = @import("./interpreter/notification.zig");
const scheduler = @import("./interpreter/scheduler.zig");
const example_tasks = @import("./interpreter/example_tasks.zig");
const uart = @import("./uart.zig");

/// The task that should get the next compute cycle.
pub var active_task: *Frame.List.Node = undefined;
/// All tasks.
pub var tasks = Frame.List.init();
/// The last as of yet never used ID
var new_id: u32 = 0;

/// This just idles all the time.
var root_task = Frame.List.Node.init(.{
    .id = 0,
    .program = &[_]Frame.Instruction{},
    .waiting = true,
});

const debug = @import("build_options").log_vm;

/// Set up the root task and (for now at least) example tasks
pub fn init() void {
    if (comptime debug) uart.print("init interpreter...\n", .{});

    tasks.prepend(&root_task);
    active_task = &root_task;
    if (comptime debug) uart.print("  set up root idle task\n", .{});

    createTask(example_tasks.echo[0..]) catch @panic("Kernel OOM");
    createTask(example_tasks.just_think[0..]) catch @panic("Kernel OOM");
    createTask(example_tasks.did_you_know[0..]) catch @panic("Kernel OOM");
}

/// Create a task to be executed based on a slice of instructions
pub fn createTask(program: []const Frame.Instruction) !void {
    new_id += 1;
    errdefer new_id -= 1;

    const task = try tasks.createNode(.{
        .program = program,
        .id = new_id,
    }, &heap.kpagealloc);
    tasks.prepend(task);
}

/// Kill a task and deallocate its resources.
pub fn destroyTask(task: *Frame.List.Node) void {
    task.data.deinit();
    tasks.remove(task);
    tasks.destroyNode(task, &heap.kpagealloc);
    active_task = &root_task;
}

/// Hand over control of this hart to the VM.
pub fn run() void {
    while (true) {
        vm.one_step(active_task);
    }
}

pub const shell = struct {
    pub fn activateTaskSwitcher() void {}
};
