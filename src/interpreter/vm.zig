//! This file is a deliberately minimal (read: effectively non-functional)
//! virtual machine that current pretends to be actual wasm processes so that
//! I can figure out the logic first and the wasm implementation details later.

const std = @import("std");
const heap = @import("../heap.zig");
const uart = @import("../uart.zig");
const interpreter = @import("../interpreter.zig");

const example_tasks = @import("./example_tasks.zig");
const Frame = @import("./Frame.zig");

const debug = @import("build_options").log_vm;

pub fn step(frame: *Frame.List.Node) void {
    var t = &frame.data;
    // this shouldn't happen unless we return from a state where
    // all tasks were waiting
    if (t.waiting) {
        interpreter.schedule();
        return;
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
            interpreter.schedule();
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
            if (comptime debug) uart.print("exited: {}\n", .{t});
            interpreter.destroyTask(frame);
            interpreter.schedule();
        },
    }
}
