//! This code manages memory on a page basis.
//! We don't bother with the MMU because no untrusted machine
//! code is run anyway. I hope so, at least.

const std = @import("std");
const assert = std.debug.assert;
const uart = @import("./uart.zig");

/// A Page descriptor, stored starting at __heap_start.
const Page = extern struct {
    flags: u8,

    pub const Flags = enum(u8) {
        empty = 0b0000_0000,
        taken = 0b0000_0001,
        last = 0b0000_00010,
    };

    pub inline fn is_taken(self: Page) bool {
        return (self.flags & @enumToInt(Flags.taken) > 0);
    }
    pub inline fn is_last(self: Page) bool {
        return (self.flags & @enumToInt(Flags.last) > 0);
    }
    pub inline fn is_free(self: Page) bool {
        return !is_taken(self);
    }
};

pub const page_size = 4096;

// take the address of these you fuckdoodle
extern const __heap_start: u8;
extern const __heap_end: u8;

var heap_start: usize = undefined;
var heap_end: usize = undefined;
var heap_size: usize = undefined;

var alloc_start: usize = undefined;
var num_pages: usize = undefined;

var descriptors: []volatile Page = undefined;

/// Initialize all page descriptors and related work. Must have been called
/// before any allocation occurs.
pub fn init() void {
    // set global variables to linker provided addresses
    heap_start = @ptrToInt(&__heap_start);
    heap_end = @ptrToInt(&__heap_end);
    heap_size = heap_end - heap_start;

    // calculate maximum number of pages
    num_pages = heap_size / page_size;

    // calculate actual allocation start without descriptors and align
    alloc_start = heap_start + num_pages * @sizeOf(Page);
    alloc_start = alloc_start + (page_size - (alloc_start % page_size));
    // calculate actual number of pages
    num_pages = (heap_end - alloc_start) / page_size;

    descriptors = @intToPtr([*]volatile Page, heap_start)[0..num_pages];
    for (descriptors) |*page, index| {
        page.* = .{ .flags = @enumToInt(Page.Flags.empty) };
    }

    uart.print(
        \\init heap...
        \\  start at 0x{x}, size 0x{x}
        \\  {} pages starting at 0x{x}
        \\
    ,
        .{ heap_start, heap_size, num_pages, alloc_start },
    );
}

/// Allocate `num` pages, returning a zeroed slice of memory or error.OutOfMemory.
pub fn alloc_pages(num: usize) ![]u8 {
    assert(num > 0);
    assert(num < num_pages);
    outer: for (descriptors) |*page, index| {
        // skip if any pages in the set aren't free
        if (page.is_taken()) continue;
        for (descriptors[index .. index + num]) |*other_page| {
            if (other_page.is_taken()) continue :outer;
        }
        // set page descriptors
        for (descriptors[index .. index + num]) |*free_page, inner_index| {
            assert(free_page.is_free());
            free_page.*.flags |= @enumToInt(Page.Flags.taken);
            if (inner_index == (num - 1)) {
                free_page.*.flags |= @enumToInt(Page.Flags.last);
            }
        }
        // zero out actual memory
        const result = @intToPtr([*]u8, alloc_start)[index * page_size .. (index + num) * page_size];
        for (result) |*b| b.* = 0;
        return result;
    }
    return error.OutOfMemory;
}

/// Returns pages into the pool of available pages and zeroes them out. Doesn't fail.
pub fn free_pages(ptr: []u8) void {
    assert(ptr.len % 4096 == 0);
    const first_page = (@ptrToInt(ptr.ptr) - alloc_start) / page_size;
    const page_count = ptr.len / 4096;
    for (descriptors[first_page .. first_page + page_count]) |*desc| {
        assert(desc.is_taken());
        desc.*.flags = @enumToInt(Page.Flags.empty);
    }
    for (ptr) |*b| b.* = 0;
}

fn debug() void {
    for (descriptors) |desc, id| {
        if (desc.is_taken()) uart.print("0x{x:0>3}\t{b:0>8}\n", .{ id, desc.flags });
    }
}
