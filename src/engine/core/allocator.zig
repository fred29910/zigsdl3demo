//! Allocator 模块：封装 std.mem.Allocator 并提供简单分配统计。
const std = @import("std");
pub const Allocator = struct {
    backing: std.mem.Allocator,
    allocated_bytes: usize = 0,
    total_alloc: usize = 0,
    total_free: usize = 0,
    pub fn init(backing: std.mem.Allocator) Allocator {
        return .{ .backing = backing };
    }
    pub fn allocator(self: *Allocator) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &vtable };
    }
    const vtable = std.mem.Allocator.VTable{
        .alloc = allocFn,
        .resize = resizeFn,
        .remap = remapFn,
        .free = freeFn,
    };
    fn allocFn(ctx: *anyopaque, len: usize, a: std.mem.Alignment, r: usize) ?[*]u8 {
        const self: *Allocator = @ptrCast(@alignCast(ctx));
        const p = self.backing.vtable.alloc(self.backing.ptr, len, a, r);
        if (p != null) { self.total_alloc += len; self.allocated_bytes += len; }
        return p;
    }
    fn freeFn(ctx: *anyopaque, m: []u8, a: std.mem.Alignment, r: usize) void {
        const self: *Allocator = @ptrCast(@alignCast(ctx));
        self.backing.vtable.free(self.backing.ptr, m, a, r);
        self.total_free += m.len;
        if (self.allocated_bytes >= m.len) self.allocated_bytes -= m.len else self.allocated_bytes = 0;
    }
    fn resizeFn(ctx: *anyopaque, m: []u8, a: std.mem.Alignment, n: usize, r: usize) bool {
        const self: *Allocator = @ptrCast(@alignCast(ctx));
        const ok = self.backing.vtable.resize(self.backing.ptr, m, a, n, r);
        if (ok) adjust(self, m.len, n);
        return ok;
    }
    fn remapFn(ctx: *anyopaque, m: []u8, a: std.mem.Alignment, n: usize, r: usize) ?[*]u8 {
        const self: *Allocator = @ptrCast(@alignCast(ctx));
        const p = self.backing.vtable.remap(self.backing.ptr, m, a, n, r);
        if (p != null) adjust(self, m.len, n);
        return p;
    }
    fn adjust(self: *Allocator, old: usize, new_len: usize) void {
        if (new_len >= old) { self.allocated_bytes += new_len - old; self.total_alloc += new_len - old; }
        else { const d = old - new_len; if (self.allocated_bytes >= d) self.allocated_bytes -= d; self.total_free += d; }
    }
    pub fn new(self: *Allocator, comptime T: type) !*T {
        return try self.allocator().create(T);
    }
    pub fn destroy(self: *Allocator, ptr: anytype) void {
        self.allocator().destroy(ptr);
    }
};
test "allocator counts" {
    var w = Allocator.init(std.testing.allocator);
    const a = w.allocator();
    const p = try a.create(i32);
    p.* = 7;
    try std.testing.expect(w.allocated_bytes >= @sizeOf(i32));
    try std.testing.expect(w.total_alloc >= @sizeOf(i32));
    a.destroy(p);
    try std.testing.expectEqual(@as(usize, 0), w.allocated_bytes);
}
test "allocator new destroy" {
    var w = Allocator.init(std.testing.allocator);
    const p = try w.new(f64);
    p.* = 3.14;
    try std.testing.expectEqual(@as(f64, 3.14), p.*);
    w.destroy(p);
    try std.testing.expectEqual(@as(usize, 0), w.allocated_bytes);
}
