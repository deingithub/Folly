with import (builtins.fetchTarball {
  # nixos-unstable on 2020-05-14
  url = "https://github.com/NixOS/nixpkgs/tarball/8ba41a1e14961fe43523f29b8b39acb569b70e72";
  sha256 = "0c2wn7si8vcx0yqwm92dpry8zqjglj9dfrvmww6ha6ihnjl6mfhh";
}) {};

mkShell rec {
  buildInputs = [ qemu ];
  shellHook = ''
    dd if=/dev/zero of=hdd.img bs=1M count=32 status=none
    alias xgdb='${import ./cross-utils/gdb}/bin/riscv64-gdb'
    alias xobjdump='${import ./cross-utils/binutils}/riscv64-elf/bin/objdump'
    alias run='${qemu}/bin/qemu-system-riscv64 ${
      lib.strings.concatStringsSep " " qemuArgs
    }'
    echo "Check if you have a recent-ish (as of March 2020) master build of zig installed."
    echo "You and I both know that it's not stable."
    echo Godspeed.
  '';
  qemuArgs = [
    "-machine virt"
    "-cpu rv64"
    "-smp 4"
    "-m 512M"
    "-nographic"
    "-serial mon:stdio"
    "-bios none"
    "-kernel zig-cache/bin/Folly"
    "-drive if=none,format=raw,file=hdd.img,id=foo"
    "-device virtio-blk-device,scsi=off,drive=foo"
    "-no-reboot"
    "-no-shutdown"
  ];
}
