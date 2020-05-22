const Frame = @import("./Frame.zig");

const ex_1_string = "Did you know that world-renowned writer Stephen King was once hit by a car?";
pub const did_you_know = [_]Frame.Instruction{
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
pub const just_think = [_]Frame.Instruction{
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
    .{ .exec = .{ .subscribe = .{ .kind = .uart_data, .address = 5 } } },
    .{ .exec = .{ .set_waiting = true } },
    .{ .yield = {} },
    .{ .push_const = 2 },
    .{ .jump = {} },
    .{ .exec = .{ .log = 1 } },
    .{ .exec = .{ .set_waiting = true } },
    .{ .jump = {} },
};
