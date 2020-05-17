# The Folly of Cass

## A RV64G kernel implemented in Zig

This is a timesink. To waste your time similarly to how I do, you need [The Nix Package Manager](https://nixos.org/nix/) and [The Zig Programming Language](https://ziglang.org).
Technically you only need the latter but the former does a lot of important stuff too and makes the entire thing … *comparatively* painless. You should use it anyway. I am being really helpful, I know.


### Executive Summary

Wow I can't decide if that sounds more self-important or soulless. I'll keep it for now, it is apt in either case. The kernel entry point is in `src/startup.asm`, which does some setup and hands over to `src/main.zig`'s `kmain()`. It goes downhill from there. Currently Folly can receive interrupts, allocate heap memory in page sized chunks and write to and read from the UART. Planned features include a userspace exclusively implemented in an interpreted language, (if possible in QEMU, TODO figure this out) graphics support for a vaguely Oberon-inspired textual user interface, and an overall oppressive and impersonal atmosphere.


### Hacking

```sh
nix-shell # this installs a metric fuckton of version-locked tools courtesy of nixpkgs
zig build && run # this builds the kernel and runs it in qemu
```