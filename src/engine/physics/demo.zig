//! Physics fixture for the bundled scene.
const std = @import("std");
const scene = @import("../scene/registry.zig");
const Transform = @import("../scene/transform.zig").Transform;
const Vec3 = @import("../scene/transform.zig").Vec3;
const MeshRenderer = @import("../scene/mesh_renderer.zig").MeshRenderer;
const assets = @import("../assets/asset_manager.zig");
const handles = @import("../assets/handle.zig");
const physics = @import("world.zig");
const Weapon = @import("../gameplay/weapon.zig").Weapon;
const Health = @import("../gameplay/health.zig").Health;
const hitscan = @import("../gameplay/hitscan.zig");
const Enemy = @import("../gameplay/enemy.zig").Enemy;
const Layout = @import("range_layout.zig").Layout;

pub const Demo = struct {
    pub const eye_height = 1.6;
    pub const Feedback = enum(u32) { none, surface, damage, defeated };
    pub const Phase = enum(u32) { playing, won, lost };

    const Actor = struct { box: Box, body: physics.BodyId };

    world: physics.World,
    crate: Actor,
    target: Actor,
    enemy_actor: ?Actor,
    enemy: Enemy,
    player: scene.Entity,
    phase: Phase = .playing,
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

    pub fn init(registry: *scene.Registry, model: *const assets.Model, handle: assets.ModelHandle, layout: *const Layout) !Demo {
        var world = try physics.World.init(registry.allocator);
        errdefer world.deinit();

        for (layout.solids) |solid| try world.bindEntity(try world.createBody(solid.desc), registry, solid.entity);
        const crate = try createActor(&world, registry, model, handle, .{
            .collider = .{ .box = @splat(0.38) },
            .layer = .dynamic,
            .pose = .{ .position = layout.crate_center },
            .angular_velocity = .{ 1.4, 0.6, 0.9 },
        }, null);
        errdefer crate.box.deinit(registry);
        const target = try createActor(&world, registry, model, handle, .{
            .collider = .{ .box = .{ 0.65, 1.05, 0.16 } },
            .pose = .{ .position = layout.target_center },
        }, layout.target_material);
        errdefer target.box.deinit(registry);
        try registry.add(target.box.root, Health.init(100));
        const enemy: Enemy = .{ .feet = layout.patrol[0] };
        const enemy_actor = try createActor(&world, registry, model, handle, .{
            .collider = .{ .box = Enemy.half },
            .layer = .dynamic,
            .kinematic = true,
            .pose = .{ .position = enemy.center() },
        }, layout.enemy_material);
        errdefer enemy_actor.box.deinit(registry);
        try registry.add(enemy_actor.box.root, Health.init(75));
        const player = try registry.create();
        errdefer registry.destroy(player) catch unreachable;
        try registry.add(player, Health.init(100));
        try world.createCharacter(layout.player_spawn, 0.32, 0.58);
        return .{ .world = world, .crate = crate, .target = target, .enemy = enemy, .enemy_actor = enemy_actor, .player = player };
    }

    fn createActor(world: *physics.World, registry: *scene.Registry, model: *const assets.Model, handle: assets.ModelHandle, desc: physics.BodyDesc, material: ?assets.MaterialHandle) !Actor {
        const box = try Box.init(registry, model, handle, desc.pose.position, desc.collider.box, material);
        errdefer box.deinit(registry);
        const body = try world.createBody(desc);
        errdefer world.destroyBody(body) catch unreachable;
        try world.bindEntity(body, registry, box.root);
        return .{ .box = box, .body = body };
    }

    pub fn updateRound(self: *Demo, registry: *scene.Registry, layout: *const Layout) !?Health.Damage {
        const feet = self.world.characterState().?.feet;
        var player = registry.get(self.player, Health).?;
        const fallen = feet[1] < layout.player_spawn[1] - 3;
        if (fallen) {
            const damage = player.applyDamage(player.current);
            try registry.add(self.player, player);
            self.phase = .lost;
            return damage;
        }
        var damage: ?Health.Damage = null;
        if (self.enemy_actor) |actor| {
            if (registry.get(actor.box.root, Health).?.current == 0) {
                try self.world.destroyBody(actor.body);
                actor.box.deinit(registry);
                self.enemy_actor = null;
                self.enemy.state = .down;
            } else {
                const elapsed = @as(f32, @floatFromInt(self.steps)) * physics.fixed_delta;
                const old_center = self.enemy.center();
                if (try self.enemy.update(&self.world, actor.body, elapsed, feet, &layout.navigation, &layout.patrol)) {
                    damage = player.applyDamage(Enemy.damage);
                    try registry.add(self.player, player);
                }
                const center = self.enemy.center();
                if (!std.meta.eql(old_center, center))
                    try self.world.setKinematicPosition(registry, actor.body, center);
            }
        }
        if (player.current == 0) self.phase = .lost else if (self.enemy_actor == null and
            registry.get(self.target.box.root, Health).?.current == 0) self.phase = .won;
        return damage;
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
        self.target.box.deinit(registry);
        self.crate.box.deinit(registry);
        if (self.enemy_actor) |actor| actor.box.deinit(registry);
    }
};

const Box = struct {
    root: scene.Entity,
    drawables: [2]scene.Entity,

    fn init(registry: *scene.Registry, model: *const assets.Model, handle: assets.ModelHandle, position: Vec3, half: Vec3, material: ?assets.MaterialHandle) !Box {
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
                .material = material orelse model.meshes[index].material,
            });
        }

        return .{ .root = root, .drawables = drawables };
    }

    fn deinit(self: Box, registry: *scene.Registry) void {
        for (self.drawables) |entity| registry.destroy(entity) catch unreachable;
        registry.destroy(self.root) catch unreachable;
    }
};
