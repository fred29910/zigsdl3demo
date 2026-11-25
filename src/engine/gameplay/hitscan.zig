const physics = @import("../physics/world.zig");
const Registry = @import("../scene/registry.zig").Registry;
const Vec3 = @import("../scene/transform.zig").Vec3;
const WeaponData = @import("weapon.zig").WeaponData;
const Health = @import("health.zig").Health;

pub const ShotEvent = struct {
    hit: ?physics.RayHit = null,
    damage: ?Health.Damage = null,
};

/// Only the closest hit can receive damage, so scenery also occludes targets.
pub fn fire(world: *const physics.World, registry: *Registry, origin: Vec3, forward: Vec3, data: WeaponData) !ShotEvent {
    const hit = (try world.raycast(origin, forward, data.range, .all)) orelse return .{};
    const entity = hit.entity orelse return .{ .hit = hit };
    var health = registry.get(entity, Health) orelse return .{ .hit = hit };
    const damage = health.applyDamage(data.damage) orelse return .{ .hit = hit };
    try registry.add(entity, health);
    return .{ .hit = hit, .damage = damage };
}
