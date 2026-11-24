const std = @import("std");
const scene = @import("../scene/registry.zig");
const resources = @import("../scene/mesh_renderer.zig");
const handles = @import("../assets/handle.zig");
const transform = @import("../scene/transform.zig");
const Matrix = transform.Matrix;

pub const RenderItem = struct {
    entity: scene.Entity,
    mesh: handles.MeshHandle,
    material: handles.MaterialHandle,
    model: Matrix,
    sort_key: u128,

    fn lessThan(_: void, a: RenderItem, b: RenderItem) bool {
        return a.sort_key < b.sort_key;
    }
};

/// Per-frame opaque draw list. The queue retains storage for reuse.
pub const RenderQueue = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList(RenderItem) = .empty,

    pub fn init(allocator: std.mem.Allocator) RenderQueue {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *RenderQueue) void {
        self.items.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn collect(self: *RenderQueue, registry: *scene.Registry) std.mem.Allocator.Error![]const RenderItem {
        self.items.clearRetainingCapacity();
        errdefer self.items.clearRetainingCapacity();
        var drawables = try registry.drawables();
        while (drawables.next()) |drawable| {
            const mesh_renderer = drawable.mesh_renderer;
            // Group opaque draws by material, then mesh. Slot iteration breaks ties.
            try self.items.append(self.allocator, .{
                .entity = drawable.entity,
                .mesh = mesh_renderer.mesh,
                .material = mesh_renderer.material,
                .model = drawable.world,
                .sort_key = (@as(u128, mesh_renderer.material.index) << 64) | mesh_renderer.mesh.index,
            });
        }
        std.mem.sort(RenderItem, self.items.items, {}, RenderItem.lessThan);
        return self.items.items;
    }
};

test "collects only complete drawables and rebuilds after registry edits" {
    var registry = scene.Registry.init(std.testing.allocator);
    defer registry.deinit();
    var queue = RenderQueue.init(std.testing.allocator);
    defer queue.deinit();
    const triangle = try registry.create();
    const cube = try registry.create();
    const child = try registry.create();
    const hidden = try registry.create();
    const material: handles.MaterialHandle = .{ .index = 0, .generation = 1 };
    const cube_mesh: handles.MeshHandle = .{ .index = 0, .generation = 1 };
    const triangle_mesh: handles.MeshHandle = .{ .index = 1, .generation = 1 };
    try registry.add(triangle, resources.MeshRenderer{ .mesh = triangle_mesh, .material = material });
    try registry.add(triangle, transform.Transform{});
    try registry.add(cube, resources.MeshRenderer{ .mesh = cube_mesh, .material = material });
    try registry.add(cube, transform.Transform{ .position = .{ 5, 0, 0 } });
    try registry.add(child, resources.MeshRenderer{ .mesh = cube_mesh, .material = material });
    try registry.add(child, transform.Transform{ .position = .{ 3, 0, 0 } });
    try registry.setParent(child, cube);
    try registry.add(hidden, resources.MeshRenderer{ .mesh = cube_mesh, .material = material });

    const items = try queue.collect(&registry);
    try std.testing.expectEqual(@as(usize, 3), items.len);
    try std.testing.expectEqual(cube, items[0].entity);
    try std.testing.expectEqual(child, items[1].entity);
    try std.testing.expectEqual(triangle, items[2].entity);
    try std.testing.expectEqual(@as(f32, 8), items[1].model.rows[0][3]);
    try registry.destroy(cube);
    try registry.remove(triangle, resources.MeshRenderer);
    const remaining = try queue.collect(&registry);
    try std.testing.expectEqual(@as(usize, 1), remaining.len);
    try std.testing.expectEqual(child, remaining[0].entity);
    try std.testing.expectEqual(@as(f32, 3), remaining[0].model.rows[0][3]);
}
