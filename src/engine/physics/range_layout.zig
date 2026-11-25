//! Collision and spawn data read from the training range's authored nodes.
const std = @import("std");
const scene = @import("../scene/registry.zig");
const transform = @import("../scene/transform.zig");
const assets = @import("../assets/asset_manager.zig");
const physics = @import("world.zig");
const navigation = @import("../gameplay/waypoints.zig");

pub const Layout = struct {
    solids: [7]Solid,
    player_spawn: transform.Vec3,
    target_center: transform.Vec3,
    crate_center: transform.Vec3,
    target_material: assets.MaterialHandle,
    enemy_material: assets.MaterialHandle,
    patrol: [4]transform.Vec3,
    navigation: navigation.Graph,

    const Solid = struct { entity: scene.Entity, desc: physics.BodyDesc };
    const solid_names = .{ "Floor", "Left", "Right", "Front", "Back", "Step", "Cover" };

    pub fn init(registry: *scene.Registry, model: *const assets.Model, entities: []const scene.Entity) !Layout {
        var result: Layout = undefined;
        inline for (solid_names, 0..) |name, i| {
            const node = try findNode(model, "Solid_" ++ name);
            const entity = entities[node];
            const primitives = model.nodes[node].primitives;
            if (primitives.count != 1) return error.InvalidRangeSolid;
            const mesh = model.meshes[primitives.first];
            const min: transform.Vec3 = mesh.bounds.min;
            const max: transform.Vec3 = mesh.bounds.max;
            const matrix = (try registry.worldMatrix(entity)) orelse return error.InvalidRangeTransform;
            var center: transform.Vec3 = undefined;
            var half: transform.Vec3 = undefined;
            for (matrix.rows[0..3], 0..) |row, axis| {
                for (row[0..3], 0..) |element, column| {
                    if (axis != column and @abs(element) > 0.00001) return error.RotatedRangeSolid;
                }
                center[axis] = row[axis] * (min[axis] + max[axis]) * 0.5 + row[3];
                half[axis] = @abs(row[axis]) * (max[axis] - min[axis]) * 0.5;
            }
            result.solids[i] = .{ .entity = entity, .desc = .{ .collider = .{ .box = half }, .pose = .{ .position = center } } };
            if (comptime std.mem.eql(u8, name, "Step")) result.target_material = mesh.material;
            if (comptime std.mem.eql(u8, name, "Cover")) result.enemy_material = mesh.material;
            if (comptime i >= 5) result.navigation.blockers[i - 5] = .init(center, half, 0.44);
        }
        result.player_spawn = try position(registry, model, entities, "PlayerSpawn");
        result.target_center = try position(registry, model, entities, "TargetCenter");
        result.crate_center = try position(registry, model, entities, "CrateCenter");
        inline for (0..4) |i| {
            const digit = std.fmt.comptimePrint("{d}", .{i});
            result.patrol[i] = try position(registry, model, entities, "Patrol_" ++ digit);
        }
        inline for (0..navigation.Graph.count) |i| {
            const digit = std.fmt.comptimePrint("{d}", .{i});
            result.navigation.points[i] = try position(registry, model, entities, "Nav_" ++ digit);
        }
        return result;
    }

    fn findNode(model: *const assets.Model, name: []const u8) !usize {
        for (model.nodes, 0..) |node, i| if (std.mem.eql(u8, node.name, name)) return i;
        return error.MissingRangeNode;
    }

    fn position(registry: *scene.Registry, model: *const assets.Model, entities: []const scene.Entity, name: []const u8) !transform.Vec3 {
        const entity = entities[try findNode(model, name)];
        const matrix = (try registry.worldMatrix(entity)) orelse return error.InvalidRangeTransform;
        return .{ matrix.rows[0][3], matrix.rows[1][3], matrix.rows[2][3] };
    }
};
