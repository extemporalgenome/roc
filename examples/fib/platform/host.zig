const std = @import("std");
const testing = std.testing;
const expectEqual = testing.expectEqual;
const expect = testing.expect;

comptime {
    // This is a workaround for https://github.com/ziglang/zig/issues/8218
    // which is only necessary on macOS.
    //
    // Once that issue is fixed, we can undo the changes in
    // 177cf12e0555147faa4d436e52fc15175c2c4ff0 and go back to passing
    // -fcompiler-rt in link.rs instead of doing this. Note that this
    // workaround is present in many host.zig files, so make sure to undo
    // it everywhere!
    if (std.builtin.os.tag == .macos) {
        _ = @import("compiler_rt");
    }
}

const mem = std.mem;
const Allocator = mem.Allocator;

extern fn roc__mainForHost_1_exposed(i64) i64;

const Align = extern struct { a: usize, b: usize };
extern fn malloc(size: usize) callconv(.C) ?*align(@alignOf(Align)) c_void;
extern fn realloc(c_ptr: [*]align(@alignOf(Align)) u8, size: usize) callconv(.C) ?*c_void;
extern fn free(c_ptr: [*]align(@alignOf(Align)) u8) callconv(.C) void;

const DEBUG: bool = false;

export fn roc_alloc(size: usize, alignment: u32) callconv(.C) ?*c_void {
    if (DEBUG) {
        var ptr = malloc(size);
        const stdout = std.io.getStdOut().writer();
        stdout.print("alloc:   {d} (alignment {d}, size {d})\n", .{ ptr, alignment, size }) catch unreachable;
        return ptr;
    } else {
        return malloc(size);
    }
}

export fn roc_realloc(c_ptr: *c_void, new_size: usize, old_size: usize, alignment: u32) callconv(.C) ?*c_void {
    if (DEBUG) {
        const stdout = std.io.getStdOut().writer();
        stdout.print("realloc: {d} (alignment {d}, old_size {d})\n", .{ c_ptr, alignment, old_size }) catch unreachable;
    }

    return realloc(@alignCast(@alignOf(Align), @ptrCast([*]u8, c_ptr)), new_size);
}

export fn roc_dealloc(c_ptr: *c_void, alignment: u32) callconv(.C) void {
    if (DEBUG) {
        const stdout = std.io.getStdOut().writer();
        stdout.print("dealloc: {d} (alignment {d})\n", .{ c_ptr, alignment }) catch unreachable;
    }

    free(@alignCast(@alignOf(Align), @ptrCast([*]u8, c_ptr)));
}

export fn roc_panic(c_ptr: *c_void, tag_id: u32) callconv(.C) void {
    _ = tag_id;

    const stderr = std.io.getStdErr().writer();
    const msg = @ptrCast([*:0]const u8, c_ptr);
    stderr.print("Application crashed with message\n\n    {s}\n\nShutting down\n", .{msg}) catch unreachable;
    std.process.exit(0);
}

pub export fn main() u8 {
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    // start time
    var ts1: std.os.timespec = undefined;
    std.os.clock_gettime(std.os.CLOCK_REALTIME, &ts1) catch unreachable;

    const result = roc__mainForHost_1_exposed(10);

    stdout.print("{d}\n", .{result}) catch unreachable;

    // end time
    var ts2: std.os.timespec = undefined;
    std.os.clock_gettime(std.os.CLOCK_REALTIME, &ts2) catch unreachable;

    const delta = to_seconds(ts2) - to_seconds(ts1);

    stderr.print("runtime: {d:.3}ms\n", .{delta * 1000}) catch unreachable;

    return 0;
}

fn to_seconds(tms: std.os.timespec) f64 {
    return @intToFloat(f64, tms.tv_sec) + (@intToFloat(f64, tms.tv_nsec) / 1_000_000_000.0);
}