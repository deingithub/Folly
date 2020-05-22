const interpreter = @import("../interpreter.zig");
const uart = @import("../uart.zig");

pub const VMNotifKind = @TagType(VMNotif);
pub const VMNotif = union(enum) {
    /// A new character from the UART is available.
    /// To handle, jump to handler and push data on the stack.
    uart_data: u8,
};

const debug = @import("build_options").log_notify;

pub fn notify(data: VMNotif) void {
    if (comptime debug)
        uart.print("notify: received {}\n", .{data});

    switch (interpreter.state) {
        .running => {
            var it = interpreter.tasks.first;
            while (it) |*node| : (it = node.*.next) {
                if (interpreter.shell.foreground_task == node.*) {
                    if (node.*.data.handlers[@enumToInt(data)]) |address| {
                        if (comptime debug)
                            uart.print("notify: adding to {}\n", .{node.*.data});

                        node.*.data.notifs.append(data) catch @panic("Kernel OOM in virt.notify()");
                        node.*.data.waiting = false;
                    }
                }
            }
        },
        .task_switching => {
            if (data == .uart_data) {
                _ = interpreter.shell.TaskSwitcher.line.read(data.uart_data) catch @panic("Kernel OOM in interpreter.notification.notify");
            }
        },
    }
}
