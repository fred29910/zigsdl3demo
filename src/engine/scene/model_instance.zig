const std = @import("std");
const Registry = @import("registry.zig").Registry;
const Entity = @import("registry.zig").Entity;
const Transform = @import("transform.zig").Transform;
const MeshRenderer = @import("mesh_renderer.zig").MeshRenderer;
const assets = @import("../assets/asset_manager.zig");
const handles = @import("../assets/handle.zig");

/// Registry entities for one placement of a cached model. The caller retains the model.
pub const Instance = struct {
    entities: std.ArrayList(Entity) = .empty,
    first_root: ?Entity = null,

    pub fn init(registry: *Registry, manager: *const assets.AssetManager, handle: handles.ModelHandle) !Instance {
        const model = manager.model(handle) orelse return error.InvalidModelHandle;
        const allocator = registry.allocator;
        const node_entities = try allocator.alloc(Entity, model.nodes.len);
        defer allocator.free(node_entities);
        var instance: Instance = .{};
        errdefer instance.deinit(registry);
        for (model.nodes, node_entities) |node, *entry| {
            const entity = try instance.create(registry);
            entry.* = entity;
            try registry.add(entity, Transform{ .local_matrix = node.local });
            if (node.parent) |parent| {
                try registry.setParent(entity, node_entities[parent]);
            } else if (instance.first_root == null) {
                instance.first_root = entity;
            }
            const range = node.primitives;
            for (range.first..range.first + range.count) |index| {
                const drawable = if (range.count == 1) entity else try instance.create(registry);
                if (range.count != 1) {
                    try registry.add(drawable, Transform{});
                    try registry.setParent(drawable, entity);
                }
                try registry.add(drawable, MeshRenderer{
                    .mesh = handles.subresource(handles.MeshHandle, handle, @intCast(index)),
                    .material = model.meshes[index].material,
                });
            }
        }
        return instance;
    }

    pub fn deinit(self: *Instance, registry: *Registry) void {
        while (self.entities.pop()) |entity| registry.destroy(entity) catch {};
        self.entities.deinit(registry.allocator);
        self.* = undefined;
    }

    fn create(self: *Instance, registry: *Registry) !Entity {
        try self.entities.ensureUnusedCapacity(registry.allocator, 1);
        const entity = try registry.create();
        self.entities.appendAssumeCapacity(entity);
        return entity;
    }
};
