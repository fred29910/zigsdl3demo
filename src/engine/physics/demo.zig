//! Physics fixture for the bundled scene.
const std = @import("std");
const scene = @import("../scene/registry.zig");
const Transform = @import("../scene/transform.zig").Transform;
const Vec3 = @import("../scene/transform.zig").Vec3;
const MeshRenderer = @import("../scene/mesh_renderer.zig").MeshRenderer;
const Instance = @import("../scene/model_instance.zig").Instance;
const assets = @import("../assets/asset_manager.zig");
const handles = @import("../assets/handle.zig");
const physics = @import("world.zig");
const Weapon = @import("../gameplay/weapon.zig").Weapon;
const Health = @import("../gameplay/health.zig").Health;
const hitscan = @import("../gameplay/hitscan.zig");

pub const Demo = struct {
    pub const eye_height = 1.6;
    pub const Feedback = enum(u32) { none, surface, damage, defeated };

    world: physics.World,
    boxes: [7]Box,
    target: scene.Entity,
    player: scene.Entity,
    steps: u32 = 0,
    ray: ?physics.RayHit = null,
    weapon: Weapon = Weapon.init(.{
        .damage = 25,
        .rounds_per_second = 4,
        .magazine_size = 6,
        .reload_seconds = 1.2,
        .range = 100,
    }),
    feedback: Feedback = .none,
    feedback_remaining: f32 = 0,

    pub fn init(registry: *scene.Registry, model: *const assets.Model, handle: assets.ModelHandle, instance: Instance) !Demo {
        var world = try physics.World.init(registry.allocator);
        errdefer world.deinit();

        // The bundled asset's third imported node is a horizontal ground quad.
        const ground_node = 2;
        const surface = model.meshes[model.nodes[ground_node].primitives.first].bounds;
        const min = surface.min;
        const max = surface.max;
        const ground_entity = instance.node_entities[ground_node];
        const ground_matrix = (try registry.worldMatrix(ground_entity)) orelse return error.MissingGroundTransform;
        const ground_corners = [_]Vec3{
            .{ min[0], min[1], min[2] }, .{ min[0], min[1], max[2] },
            .{ max[0], min[1], max[2] }, .{ max[0], min[1], min[2] },
        };
        var corners: [4]Vec3 = undefined;
        for (ground_corners, &corners) |p, *out| {
            for (ground_matrix.rows, 0..) |row, i| out[i] = row[0] * p[0] + row[1] * p[1] + row[2] * p[2] + row[3];
        }
        const floor = try world.createBody(.{
            .collider = .{ .mesh = .{ .vertices = &corners, .indices = &.{ 0, 1, 2, 0, 2, 3 } } },
        });
        try world.bindEntity(floor, registry, ground_entity);

        const left, _, const front = corners[0];
        const right, const ground, const back = corners[2];
        const center_x = (left + right) * 0.5;
        const center_z = (front + back) * 0.5;
        const half_width = (right - left) * 0.5;
        const half_depth = (back - front) * 0.5;
        const wall_half_height = 1.3;
        const wall_half_thickness = 0.18;
        const wall_y = ground + wall_half_height;
        const fixtures = [_]physics.BodyDesc{
            .{ .collider = .{ .box = .{ wall_half_thickness, wall_half_height, half_depth } }, .pose = .{ .position = .{ left, wall_y, center_z } } },
            .{ .collider = .{ .box = .{ wall_half_thickness, wall_half_height, half_depth } }, .pose = .{ .position = .{ right, wall_y, center_z } } },
            .{ .collider = .{ .box = .{ half_width, wall_half_height, wall_half_thickness } }, .pose = .{ .position = .{ center_x, wall_y, front } } },
            .{ .collider = .{ .box = .{ half_width, wall_half_height, wall_half_thickness } }, .pose = .{ .position = .{ center_x, wall_y, back } } },
            .{ .collider = .{ .box = .{ 0.8, 0.3, 0.65 } }, .pose = .{ .position = .{ -2, ground + 0.3, 1.25 } } },
            .{
                .collider = .{ .box = @splat(0.38) },
                .layer = .dynamic,
                .pose = .{ .position = .{ 2.25, 2.3, 0.05 } },
                .angular_velocity = .{ 1.4, 0.6, 0.9 },
            },
            .{ .collider = .{ .box = .{ 0.65, 1.05, 0.16 } }, .pose = .{ .position = .{ center_x, ground + 1.05, back - 0.34 } } },
        };
        var boxes: [fixtures.len]Box = undefined;
        var count: usize = 0;
        errdefer for (boxes[0..count]) |box| box.deinit(registry);
        for (fixtures, &boxes) |desc, *box| {
            box.* = try Box.init(registry, model, handle, desc.pose.position, desc.collider.box);
            count += 1;
            try world.bindEntity(try world.createBody(desc), registry, box.root);
        }
        const target = boxes[boxes.len - 1].root;
        try registry.add(target, Health.init(100));
        const player = try registry.create();
        errdefer registry.destroy(player) catch unreachable;
        try registry.add(player, Health.init(100));
        try world.createCharacter(.{ center_x, ground, front + 1.25 }, 0.32, 0.58);
        return .{ .world = world, .boxes = boxes, .target = target, .player = player };
    }

    pub fn updateWeapon(self: *Demo, registry: *scene.Registry, dt: f32, trigger: bool, reload: bool, eye: Vec3, forward: Vec3) !?hitscan.ShotEvent {
        self.feedback_remaining = @max(0, self.feedback_remaining - dt);
        if (self.feedback_remaining == 0) self.feedback = .none;
        if (!self.weapon.update(dt, trigger, reload)) return null;

        const shot = try hitscan.fire(&self.world, registry, eye, forward, self.weapon.data);
        self.ray = shot.hit;
        self.feedback = if (shot.damage) |damage|
            (if (damage.remaining == 0) .defeated else .damage)
        else if (shot.hit != null) .surface else .none;
        self.feedback_remaining = if (self.feedback == .none) 0 else 0.22;
        return shot;
    }

    pub fn deinit(self: *Demo, registry: *scene.Registry) void {
        self.world.deinit();
        registry.destroy(self.player) catch unreachable;
        for (self.boxes) |box| box.deinit(registry);
    }
};

const Box = struct {
    root: scene.Entity,
    drawables: [2]scene.Entity,

    fn init(registry: *scene.Registry, model: *const assets.Model, handle: assets.ModelHandle, position: Vec3, half: Vec3) !Box {
        const root = try registry.create();
        errdefer registry.destroy(root) catch unreachable;
        try registry.add(root, Transform{ .position = position, .scale = half });

        var drawables: [2]scene.Entity = undefined;
        var created: usize = 0;
        errdefer for (drawables[0..created]) |entity| registry.destroy(entity) catch unreachable;
        const cube = model.nodes[0].primitives;
        if (cube.count != drawables.len) return error.UnexpectedDemoMesh;
        for (&drawables, cube.first..cube.first + cube.count) |*entity, index| {
            entity.* = try registry.create();
            created += 1;
            try registry.add(entity.*, Transform{});
            try registry.setParent(entity.*, root);
            try registry.add(entity.*, MeshRenderer{
                .mesh = handles.subresource(handles.MeshHandle, handle, @intCast(index)),
                .material = model.meshes[index].material,
            });
        }

        return .{ .root = root, .drawables = drawables };
    }

    fn deinit(self: Box, registry: *scene.Registry) void {
        for (self.drawables) |entity| registry.destroy(entity) catch unreachable;
        registry.destroy(self.root) catch unreachable;
    }
};
