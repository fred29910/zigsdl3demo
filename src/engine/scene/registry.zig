const std = @import("std");
const transform = @import("transform.zig");
const MeshRenderer = @import("mesh_renderer.zig").MeshRenderer;
const Transform = transform.Transform;
const Matrix = transform.Matrix;

pub const Entity = struct {
    index: u32,
    generation: u32,
};

/// Slot-based storage for the engine's first two component types.
pub const Registry = struct {
    allocator: std.mem.Allocator,
    slots: std.ArrayList(Slot) = .empty,
    free_head: ?u32 = null,
    worlds_dirty: bool = false,
    ancestors: std.ArrayList(u32) = .empty,

    const Slot = struct {
        generation: u32 = 1,
        alive: bool = true,
        next_free: ?u32 = null,
        transform: ?Transform = null,
        mesh_renderer: ?MeshRenderer = null,
        parent: ?Entity = null,
        world: Matrix = undefined,
        dirty: bool = true,

        fn component(self: anytype, comptime T: type) if (@TypeOf(self) == *const Slot) *const ?T else *?T {
            return switch (T) {
                Transform => &self.transform,
                MeshRenderer => &self.mesh_renderer,
                else => @compileError("unsupported scene component"),
            };
        }
    };

    pub fn init(allocator: std.mem.Allocator) Registry {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Registry) void {
        self.ancestors.deinit(self.allocator);
        self.slots.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn create(self: *Registry) !Entity {
        if (self.free_head) |index| {
            const slot = &self.slots.items[index];
            self.free_head = slot.next_free;
            slot.* = .{ .generation = slot.generation };
            return .{ .index = index, .generation = slot.generation };
        }
        const index = std.math.cast(u32, self.slots.items.len) orelse return error.EntityLimit;
        try self.slots.append(self.allocator, .{});
        return .{ .index = index, .generation = 1 };
    }

    pub fn isAlive(self: *const Registry, entity: Entity) bool {
        if (entity.index >= self.slots.items.len) return false;
        const slot = &self.slots.items[entity.index];
        return slot.alive and slot.generation == entity.generation;
    }

    pub fn destroy(self: *Registry, entity: Entity) error{InvalidEntity}!void {
        if (!self.isAlive(entity)) return error.InvalidEntity;
        try self.remove(entity, Transform);
        const slot = &self.slots.items[entity.index];
        slot.mesh_renderer = null;
        slot.alive = false;
        // Retire an exhausted slot so an old handle can never become live again.
        if (slot.generation < std.math.maxInt(u32)) {
            slot.generation += 1;
            slot.next_free = self.free_head;
            self.free_head = entity.index;
        }
    }

    /// Insert or replace a component. Component values are copied in and out.
    pub fn add(self: *Registry, entity: Entity, value: anytype) error{InvalidEntity}!void {
        if (!self.isAlive(entity)) return error.InvalidEntity;
        const T = @TypeOf(value);
        self.slots.items[entity.index].component(T).* = value;
        if (T == Transform) self.worlds_dirty = true;
    }

    pub fn get(self: *const Registry, entity: Entity, comptime T: type) ?T {
        if (!self.isAlive(entity)) return null;
        return self.slots.items[entity.index].component(T).*;
    }

    pub fn has(self: *const Registry, entity: Entity, comptime T: type) bool {
        return self.get(entity, T) != null;
    }

    /// Removing a Transform detaches its direct children, preserving their local transforms.
    pub fn remove(self: *Registry, entity: Entity, comptime T: type) error{InvalidEntity}!void {
        if (!self.isAlive(entity)) return error.InvalidEntity;
        const slot = &self.slots.items[entity.index];
        const component = slot.component(T);
        if (component.* == null) return;
        component.* = null;
        if (T == Transform) {
            slot.parent = null;
            for (self.slots.items) |*child| {
                if (child.parent) |parent| {
                    if (parent.index == entity.index) child.parent = null;
                }
            }
            self.worlds_dirty = true;
        }
    }

    /// Attach or detach an entity while keeping its local transform.
    pub fn setParent(self: *Registry, entity: Entity, parent: ?Entity) !void {
        if (!self.isAlive(entity)) return error.InvalidEntity;
        const slot = &self.slots.items[entity.index];
        if (slot.transform == null) return error.MissingTransform;
        if (parent) |p| {
            if (!self.isAlive(p)) return error.InvalidEntity;
            if (!self.has(p, Transform)) return error.MissingTransform;
        }
        var ancestor = parent;
        while (ancestor) |a| {
            if (a.index == entity.index) return error.TransformCycle;
            ancestor = self.slots.items[a.index].parent;
        }
        slot.parent = parent;
        self.worlds_dirty = true;
    }

    /// Resolve each live world matrix once per dirty update, independent of slot order.
    pub fn updateWorlds(self: *Registry) std.mem.Allocator.Error!void {
        if (!self.worlds_dirty) return;
        try self.ancestors.ensureTotalCapacity(self.allocator, self.slots.items.len);
        const slots = self.slots.items;
        for (slots) |*slot| slot.dirty = slot.transform != null;
        for (slots, 0..) |*slot, index| {
            if (!slot.dirty) continue;
            var current: ?u32 = @intCast(index);
            while (current) |i| {
                if (!slots[i].dirty) break;
                self.ancestors.appendAssumeCapacity(i);
                current = if (slots[i].parent) |p| p.index else null;
            }
            while (self.ancestors.pop()) |i| {
                const entry = &slots[i];
                const local = entry.transform.?.matrix();
                entry.world = if (entry.parent) |p| slots[p.index].world.mul(local) else local;
                entry.dirty = false;
            }
        }
        self.worlds_dirty = false;
    }

    pub fn worldMatrix(self: *Registry, entity: Entity) !?Matrix {
        if (!self.has(entity, Transform)) return null;
        try self.updateWorlds();
        return self.slots.items[entity.index].world;
    }

    pub const Drawable = struct { entity: Entity, mesh_renderer: MeshRenderer, world: Matrix };

    pub const Drawables = struct {
        registry: *const Registry,
        index: usize = 0,

        pub fn next(self: *Drawables) ?Drawable {
            const slots = self.registry.slots.items;
            while (self.index < slots.len) {
                const index = self.index;
                self.index += 1;
                const slot = &slots[index];
                if (slot.transform == null) continue;
                const mesh_renderer = slot.mesh_renderer orelse continue;
                return .{
                    .entity = .{ .index = @intCast(index), .generation = slot.generation },
                    .mesh_renderer = mesh_renderer,
                    .world = slot.world,
                };
            }
            return null;
        }
    };

    /// The iterator is valid until the next registry mutation.
    pub fn drawables(self: *Registry) std.mem.Allocator.Error!Drawables {
        try self.updateWorlds();
        return .{ .registry = self };
    }
};

test "reused entities reject stale component operations" {
    var registry = Registry.init(std.testing.allocator);
    defer registry.deinit();
    const old = try registry.create();
    try registry.add(old, MeshRenderer{
        .mesh = .{ .index = 0, .generation = 1 },
        .material = .{ .index = 0, .generation = 1 },
    });
    try registry.destroy(old);
    const fresh = try registry.create();
    try std.testing.expectEqual(old.index, fresh.index);
    try std.testing.expect(old.generation != fresh.generation);
    try std.testing.expect(!registry.has(fresh, MeshRenderer));
    try std.testing.expect(!registry.has(old, MeshRenderer));
    try std.testing.expectError(error.InvalidEntity, registry.add(old, Transform{}));
    try std.testing.expectError(error.InvalidEntity, registry.remove(old, Transform));
    try std.testing.expectError(error.InvalidEntity, registry.destroy(old));
}

test "hierarchy updates out-of-order descendants and rejects cycles" {
    var registry = Registry.init(std.testing.allocator);
    defer registry.deinit();
    const leaf = try registry.create();
    const child = try registry.create();
    const root = try registry.create();
    try registry.add(leaf, Transform{ .position = .{ 0, 0, 2 } });
    try registry.add(child, Transform{ .position = .{ 2, 0, 0 } });
    try registry.add(root, Transform{ .position = .{ 1, 0, 0 }, .scale = .{ 2, 2, 2 } });
    try registry.setParent(leaf, child);
    try registry.setParent(child, root);
    try std.testing.expectError(error.TransformCycle, registry.setParent(root, leaf));
    try std.testing.expectError(error.TransformCycle, registry.setParent(root, root));
    try std.testing.expectEqual([4]f32{ 2, 0, 0, 5 }, (try registry.worldMatrix(leaf)).?.rows[0]);
    try std.testing.expectEqual([4]f32{ 0, 0, 2, 4 }, (try registry.worldMatrix(leaf)).?.rows[2]);
    try registry.add(root, Transform{ .position = .{ 10, 0, 0 } });
    try std.testing.expectEqual([4]f32{ 1, 0, 0, 12 }, (try registry.worldMatrix(leaf)).?.rows[0]);
    try registry.destroy(root);
    const replacement = try registry.create();
    try registry.add(replacement, Transform{ .position = .{ 20, 0, 0 } });
    try std.testing.expectError(error.InvalidEntity, registry.setParent(child, root));
    try std.testing.expectEqual([4]f32{ 1, 0, 0, 2 }, (try registry.worldMatrix(leaf)).?.rows[0]);
    try registry.remove(child, Transform);
    try std.testing.expectEqual([4]f32{ 1, 0, 0, 0 }, (try registry.worldMatrix(leaf)).?.rows[0]);
}
