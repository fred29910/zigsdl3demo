const std = @import("std");
const scene = @import("../scene/registry.zig");
const resources = @import("../scene/mesh_renderer.zig");
const transform = @import("../scene/transform.zig");
const Matrix = transform.Matrix;

pub const RenderItem = struct {
    entity: scene.Entity,
    mesh: resources.MeshId,
    material: resources.MaterialId,
    model: Matrix,
    sort_key: u64,

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
            // Group opaque draws by material, then mesh, breaking ties by index.
            const material: u16 = @backingInt(mesh_renderer.material);
            const mesh: u16 = @backingInt(mesh_renderer.mesh);
            try self.items.append(self.allocator, .{
                .entity = drawable.entity,
                .mesh = mesh_renderer.mesh,
                .material = mesh_renderer.material,
                .model = drawable.world,
                .sort_key = (@as(u64, material) << 48) | (@as(u64, mesh) << 32) | drawable.entity.index,
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
    try registry.add(triangle, resources.MeshRenderer{ .mesh = .triangle });
    try registry.add(triangle, transform.Transform{});
    try registry.add(cube, resources.MeshRenderer{ .mesh = .cube });
    try registry.add(cube, transform.Transform{ .position = .{ 5, 0, 0 } });
    try registry.add(child, resources.MeshRenderer{ .mesh = .cube });
    try registry.add(child, transform.Transform{ .position = .{ 3, 0, 0 } });
    try registry.setParent(child, cube);
    try registry.add(hidden, resources.MeshRenderer{ .mesh = .cube });

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
