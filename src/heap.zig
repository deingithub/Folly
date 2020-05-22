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

    pub inline fn isTaken(self: Page) bool {
        return (self.flags & @enumToInt(Flags.taken) > 0);
    }
    pub inline fn isLast(self: Page) bool {
        return (self.flags & @enumToInt(Flags.last) > 0);
    }
    pub inline fn isFree(self: Page) bool {
        return !isTaken(self);
    }
};

pub const page_size = 4096;
/// whether or not to spam debug information to UART in methods
const debug = @import("build_options").log_heap;

// take the address of these you fuckdoodle
extern const __heap_start: u8;
extern const __heap_end: u8;

var heap_start: usize = undefined;
var heap_end: usize = undefined;
var heap_size: usize = undefined;

var alloc_start: usize = undefined;
var num_pages: usize = undefined;

var descriptors: []volatile Page = undefined;

/// This mirrors std.heap.page_allocator in that it always allocates at least one page
pub var kpagealloc = std.mem.Allocator{
    .reallocFn = kPageAllocRealloc,
    .shrinkFn = kPageAllocShrink,
};
fn kPageAllocRealloc(self: *std.mem.Allocator, old_mem: []u8, old_alignment: u29, new_byte_count: usize, new_alignment: u29) std.mem.Allocator.Error![]u8 {
    if (comptime debug)
        uart.print("kPageAllocRealloc invoked: old_mem {}:{}, new_byte_count {}\n", .{ old_mem.ptr, old_mem.len, new_byte_count });

    if (new_alignment > page_size) return error.OutOfMemory; // why would you even
    if (old_mem.len == 0 or new_byte_count > page_size) {
        // create a new allocation
        const ptr = (try allocPages((new_byte_count / page_size) + 1))[0..new_byte_count];
        // move pre-existing allocation if it exists
        for (old_mem) |b, i| ptr[i] = b;
        return ptr;
    }
    if (new_byte_count <= page_size) {
        // shrink this allocation
        if (old_mem.len <= page_size) {
            // it's all on one page so pretend we actually shrunk the page
            return @ptrCast([*]u8, old_mem)[0..new_byte_count];
        } else {
            // we have extra pages left over
            return kPageAllocShrink(self, old_mem, old_alignment, new_byte_count, new_alignment);
        }
    }
    return error.OutOfMemory;
}
fn kPageAllocShrink(self: *std.mem.Allocator, old_mem: []u8, old_alignment: u29, new_byte_count: usize, new_alignment: u29) []u8 {
    if (comptime debug)
        uart.print("kPageAllocShrink invoked: old_mem {}:{}, new_byte_count {}\n", .{ old_mem.ptr, old_mem.len, new_byte_count });

    if (new_byte_count == 0 or old_mem.len / page_size > new_byte_count / page_size) {
        // free pages at the end
        const free_start = (@ptrToInt(old_mem.ptr) + new_byte_count) + ((@ptrToInt(old_mem.ptr) + new_byte_count) % page_size);
        const free_size = old_mem.len - new_byte_count;
        freePages(@intToPtr([*]u8, free_start)[0..free_size]);
    }
    return old_mem[0..new_byte_count];
}

/// Initialize all page descriptors and related work. Must have been called
/// before any allocation occurs.
pub fn init() void {
    // set global variables to linker provided addresses
    heap_start = @ptrToInt(&__heap_start);
    assert(heap_start % page_size == 0);
    heap_end = @ptrToInt(&__heap_end);
    assert(heap_end % page_size == 0);

    assert(heap_start < heap_end);
    heap_size = heap_end - heap_start;

    // calculate maximum number of pages
    num_pages = heap_size / page_size;

    // calculate actual allocation start without descriptors and align it
    alloc_start = heap_start + num_pages * @sizeOf(Page);
    alloc_start = alloc_start + (page_size - (alloc_start % page_size));
    assert(alloc_start % page_size == 0);
    // calculate actual number of pages
    num_pages = (heap_end - alloc_start) / page_size;

    descriptors = @intToPtr([*]volatile Page, heap_start)[0..num_pages];
    for (descriptors) |*page, index| {
        page.* = .{ .flags = @enumToInt(Page.Flags.empty) };
    }

    if (comptime debug)
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
pub fn allocPages(num: usize) ![]u8 {
    if (comptime debug)
        uart.print("alloc_pages invoked with num {}\n", .{num});
    defer {
        if (comptime debug) dumpPageTable();
    }

    assert(num > 0);
    if (num > num_pages) return error.OutOfMemory;
    var already_visited: usize = 0;
    outer: for (descriptors) |*page, index| {
        // skip if any pages in the set aren't free or we've already explored them and they were taken
        if (page.isTaken() or already_visited > index) continue;
        for (descriptors[index .. index + num]) |*other_page| {
            if (other_page.isTaken()) {
                already_visited += 1;
                continue :outer;
            }
        }
        // set page descriptors
        for (descriptors[index .. index + num]) |*free_page, inner_index| {
            assert(free_page.isFree());
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
/// Pointer must be one that's been returned from heap.alloc_pages().
pub fn freePages(ptr: []u8) void {
    if (comptime debug)
        uart.print("free_pages invoked with ptr {}:{}\n", .{ ptr.ptr, ptr.len });
    defer {
        if (comptime debug) dumpPageTable();
    }

    assert(@ptrToInt(ptr.ptr) % page_size == 0);
    const page_count = (ptr.len / page_size) + 1;
    const first_page = (@ptrToInt(ptr.ptr) - alloc_start) / page_size;
    for (descriptors[first_page .. first_page + page_count]) |*desc, index| {
        assert(desc.isTaken());
        if (index == page_count - 1) assert(desc.isLast());
        desc.*.flags = @enumToInt(Page.Flags.empty);
    }
    for (ptr) |*b| b.* = 0;
}

pub fn statistics(kind: enum { pages_taken, pages_total }) usize {
    return switch (kind) {
        .pages_total => num_pages,
        .pages_taken => blk: {
            var c: usize = 0;
            for (descriptors) |desc| {
                if (desc.isTaken()) c += 1;
            }
            break :blk c;
        },
    };
}

fn dumpPageTable() void {
    for (descriptors) |desc, id| {
        if (desc.isTaken()) uart.print("0x{x:0>3}\t{b:0>8}\n", .{ id, desc.flags });
    }
}
