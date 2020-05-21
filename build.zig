const std = @import("std");
const Builder = std.build.Builder;
const CrossTarget = std.zig.CrossTarget;

const log_options = [_][]const u8{
    "vm", "sched", "clint", "plic", "heap", "rupt", "uart",
};

pub fn build(b: *Builder) !void {
    const exe = b.addExecutable("Folly", "src/main.zig");
    exe.setTarget(try CrossTarget.parse(.{
        .arch_os_abi = "riscv64-freestanding",
    }));
    exe.code_model = .medium;
    exe.setLinkerScriptPath("linker.ld");
    exe.setBuildMode(.Debug);
    exe.install();

    const log_all = b.option(bool, "log-all", "Spam logging for all of the following to UART. Beware.") orelse false;
    inline for (log_options) |opt| {
        exe.addBuildOption(
            bool,
            "log_" ++ opt,
            log_all or b.option(bool, "log-" ++ opt, "Spam logging for this particular thing to UART") orelse false,
        );
    }

    const run = b.addSystemCommand(&[_][]const u8{
        blk: {
            if (b.env_map.get("QEMU_EXE")) |path| {
                if (std.mem.endsWith(u8, path, "qemu-system-riscv64")) break :blk path;
            }
            std.debug.warn("Please specify the path to `qemu-system-riscv64` in the environment variable QEMU_EXE.\n", .{});
            return error.MissingQEMU;
        },
        "-kernel",
    });
    run.addArtifactArg(exe);
    run.addArgs(&qemu_args);

    const i_dont_know_what_im_doing_help = b.step("run", "Build and launch Folly in QEMU");
    i_dont_know_what_im_doing_help.dependOn(&run.step);
}

// zig fmt: off
const qemu_args = [_][]const u8{
    "-machine", "virt",
    "-cpu", "rv64",
    "-smp", "4",
    "-m", "512M",
    "-nographic",
    "-serial", "mon:stdio",
    "-bios", "none",
    "-drive", "if=none,format=raw,file=hdd.img,id=foo",
    "-device", "virtio-blk-device,scsi=off,drive=foo",
    "-no-reboot",
    "-no-shutdown",
};
// zig fmt: on
