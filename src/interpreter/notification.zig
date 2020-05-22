const interpreter = @import("../interpreter.zig");

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

    var it = interpreter.tasks.first;
    while (it) |*node| : (it = node.*.next) {
        if (node.*.data.handlers[@enumToInt(data)]) |address| {
            if (comptime debug)
                uart.print("notify: adding to {}\n", .{node.*.data});

            node.*.data.notifs.append(data) catch @panic("Kernel OOM in virt.notify()");
            node.*.data.waiting = false;
        }
    }
}
