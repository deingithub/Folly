const std = @import("std");
const Builder = std.build.Builder;
const CrossTarget = std.zig.CrossTarget;

pub fn build(b: *Builder) !void {
    const exe = b.addExecutable("Folly", "src/main.zig");
    exe.setTarget(try CrossTarget.parse(.{
        .arch_os_abi = "riscv64-freestanding",
    }));
    exe.code_model = .medium;
    exe.setLinkerScriptPath("linker.ld");
    exe.setBuildMode(.Debug);
    exe.install();
}
