const std = @import("std");
const physics = @import("engine/physics/world.zig");
const scene = @import("engine/scene/registry.zig");
const Transform = @import("engine/scene/transform.zig").Transform;
const Weapon = @import("engine/gameplay/weapon.zig").Weapon;
const WeaponData = @import("engine/gameplay/weapon.zig").WeaponData;
const Health = @import("engine/gameplay/health.zig").Health;
const hitscan = @import("engine/gameplay/hitscan.zig");
const testing = std.testing;

const test_weapon: WeaponData = .{
    .damage = 25,
    .rounds_per_second = 4,
    .magazine_size = 2,
    .reload_seconds = 1,
    .range = 10,
};

test "weapon enforces shot cadence, empty magazine, and reload duration" {
    var weapon = Weapon.init(test_weapon);
    try testing.expect(!weapon.update(0, false, true)); // Full magazine.
    try testing.expectEqual(.idle, weapon.state);
    try testing.expect(weapon.update(0, true, false));
    try testing.expectEqual(.firing, weapon.state);
    try testing.expectEqual(@as(u16, 1), weapon.rounds);
    try testing.expect(!weapon.update(0.125, true, false));
    try testing.expect(weapon.update(0.125, true, false));
    try testing.expect(!weapon.update(0.25, true, false)); // Empty.
    try testing.expectEqual(@as(u16, 0), weapon.rounds);

    try testing.expect(!weapon.update(0, true, true)); // Reload takes priority.
    try testing.expectEqual(.reloading, weapon.state);
    try testing.expect(!weapon.update(0.75, true, true)); // Repeat cannot restart a reload.
    try testing.expectEqual(@as(u16, 0), weapon.rounds);
    try testing.expect(!weapon.update(0.25, true, false)); // Refill, no shot this frame.
    try testing.expectEqual(.idle, weapon.state);
    try testing.expectEqual(test_weapon.magazine_size, weapon.rounds);
    try testing.expect(weapon.update(0, true, false));
}

test "hitscan respects range and occlusion and emits only applied damage" {
    var world = try physics.World.init(testing.allocator);
    defer world.deinit();
    var registry = scene.Registry.init(testing.allocator);
    defer registry.deinit();
    const target = try registry.create();
    try registry.add(target, Transform{});
    try registry.add(target, Health.init(40));
    const target_body = try world.createBody(.{
        .collider = .{ .box = @splat(0.5) },
        .pose = .{ .position = .{ 0, 0, 8 } },
    });
    try world.bindEntity(target_body, &registry, target);
    const wall = try world.createBody(.{
        .collider = .{ .box = @splat(0.5) },
        .pose = .{ .position = .{ 0, 0, 4 } },
    });

    const origin = [3]f32{ 0, 0, 0 };
    const forward = [3]f32{ 0, 0, 1 };
    const blocked = try hitscan.fire(&world, &registry, origin, forward, test_weapon);
    try testing.expectEqual(wall, blocked.hit.?.body);
    try testing.expectEqual(null, blocked.damage);
    try testing.expectEqual(@as(u16, 40), registry.get(target, Health).?.current);

    var shorter = test_weapon;
    shorter.range = 2;
    const miss = try hitscan.fire(&world, &registry, origin, forward, shorter);
    try testing.expectEqual(null, miss.hit);
    try testing.expectEqual(null, miss.damage);

    const clear_origin = [3]f32{ 0, 0, 5 };
    const first = try hitscan.fire(&world, &registry, clear_origin, forward, test_weapon);
    try testing.expectEqual(target, first.hit.?.entity.?);
    try testing.expectEqual(Health.Damage{ .applied = 25, .remaining = 15 }, first.damage.?);
    const down = try hitscan.fire(&world, &registry, clear_origin, forward, test_weapon);
    try testing.expectEqual(Health.Damage{ .applied = 15, .remaining = 0 }, down.damage.?);
    try testing.expectEqual(@as(u16, 0), registry.get(target, Health).?.current);
    const spent = try hitscan.fire(&world, &registry, clear_origin, forward, test_weapon);
    try testing.expectEqual(target_body, spent.hit.?.body);
    try testing.expectEqual(null, spent.damage);
}

test "character walks, sprints, and slides against a wall on triangle terrain" {
    var world = try physics.World.init(testing.allocator);
    defer world.deinit();
    const floor_vertices: [4][3]f32 = .{ .{ -16, 0, -16 }, .{ -16, 0, 16 }, .{ 16, 0, 16 }, .{ 16, 0, -16 } };
    _ = try world.createBody(.{ .collider = .{ .mesh = .{ .vertices = &floor_vertices, .indices = &.{ 0, 1, 2, 0, 2, 3 } } } });
    _ = try world.createBody(.{ .collider = .{ .box = .{ 0.2, 1.5, 10 } }, .pose = .{ .position = .{ 3, 1.5, 0 } } });
    try world.createCharacter(.{ 0, 0, 0 }, 0.32, 0.58);
    try testing.expectEqual(@as(usize, 2), world.bodyCount());
    try testing.expectError(error.CharacterAlreadyExists, world.createCharacter(.{ 0, 0, 1 }, 0.32, 0.58));

    // Diagonal input still covers three metres per second.
    try world.setCharacterInput(.{ .strafe = -1, .forward = -1 });
    for (0..60) |_| _ = try world.advance(physics.fixed_delta);
    const walked = world.characterState().?;
    const diagonal = 3 / @sqrt(@as(f32, 2));
    try testing.expectApproxEqAbs(-diagonal, walked.feet[0], 0.03);
    try testing.expectApproxEqAbs(-diagonal, walked.feet[2], 0.03);
    try testing.expect(walked.grounded);

    // Facing +X, forward input sprints into the wall, stopping at capsule radius.
    try world.setCharacterInput(.{ .forward = 1, .yaw = std.math.pi / 2.0, .sprint = true });
    for (0..30) |_| _ = try world.advance(physics.fixed_delta);
    try testing.expectApproxEqAbs(walked.feet[0] + 3.5, world.characterState().?.feet[0], 0.04);
    for (0..60) |_| _ = try world.advance(physics.fixed_delta);
    const blocked = world.characterState().?;
    try testing.expectApproxEqAbs(@as(f32, 2.48), blocked.feet[0], 0.04);
    try testing.expect(blocked.grounded);

    try world.setCharacterInput(.{ .strafe = 1, .forward = 1, .sprint = true, .jump_pressed = true });
    for (0..60) |_| {
        _ = try world.advance(physics.fixed_delta);
        try testing.expect(world.characterState().?.feet[0] <= 2.50);
    }
    const slid = world.characterState().?;
    try testing.expect(slid.feet[2] > blocked.feet[2] + 4);
    try testing.expectApproxEqAbs(@as(f32, 0), slid.feet[1], 0.04);
    try testing.expect(slid.grounded);
}

test "jump survives a substep frame, is consumed once, and is cancelled on capture loss" {
    var world = try physics.World.init(testing.allocator);
    defer world.deinit();
    _ = try world.createBody(.{ .collider = .{ .box = .{ 4, 0.25, 4 } }, .pose = .{ .position = .{ 0, -0.25, 0 } } });
    try world.createCharacter(.{ 0, 0, 0 }, 0.32, 0.58);
    try testing.expect(world.characterState().?.grounded);

    try world.setCharacterInput(.{ .jump_pressed = true });
    try testing.expectEqual(@as(u32, 0), try world.advance(physics.fixed_delta * 0.5));
    try world.setCharacterInput(.{});
    _ = try world.advance(physics.fixed_delta * 0.5);
    var apex: f32 = 0;
    var landings: usize = 0;
    var was_grounded = world.characterState().?.grounded;
    for (0..120) |i| {
        if (i == 10) try world.setCharacterInput(.{ .jump_pressed = true });
        _ = try world.advance(physics.fixed_delta);
        const character = world.characterState().?;
        apex = @max(apex, character.feet[1]);
        if (!was_grounded and character.grounded) landings += 1;
        was_grounded = character.grounded;
    }
    try testing.expect(apex > 1 and apex < 1.3);
    try testing.expectEqual(@as(usize, 1), landings);
    try testing.expect(world.characterState().?.grounded);

    try world.setCharacterInput(.{ .forward = 1, .jump_pressed = true });
    try world.setCharacterInput(null);
    _ = try world.advance(0.1);
    const stopped = world.characterState().?;
    try testing.expect(stopped.grounded);
    try testing.expectApproxEqAbs(@as(f32, 0), stopped.feet[2], 0.01);

    _ = try world.createBody(.{ .collider = .{ .box = .{ 0.8, 0.3, 0.65 } }, .pose = .{ .position = .{ 0, 0.3, 1.75 } } });
    try world.setCharacterInput(.{ .forward = 1 });
    for (0..30) |_| _ = try world.advance(physics.fixed_delta);
    try testing.expectApproxEqAbs(@as(f32, 0.78), world.characterState().?.feet[2], 0.04);
    try world.setCharacterInput(.{ .forward = 1, .jump_pressed = true });
    for (0..26) |_| _ = try world.advance(physics.fixed_delta);
    try world.setCharacterInput(.{});
    for (0..60) |_| _ = try world.advance(physics.fixed_delta);
    const on_box = world.characterState().?;
    try testing.expectApproxEqAbs(@as(f32, 0.6), on_box.feet[1], 0.04);
    try testing.expect(on_box.grounded);
}

test "empty Jolt worlds step independently and can be recreated" {
    for (0..2) |_| {
        var first = try physics.World.init(testing.allocator);
        defer first.deinit();
        var second = try physics.World.init(testing.allocator);
        defer second.deinit();
        try testing.expectEqual(@as(u32, 0), try first.advance(physics.fixed_delta * 0.5));
        try testing.expectEqual(@as(u32, 1), try first.advance(physics.fixed_delta * 0.5));
        try testing.expectEqual(@as(u32, 6), try second.advance(10));
        try testing.expectEqual(@as(u32, 0), try second.advance(0));
        try testing.expect((try first.raycast(.{ 0, 0, 0 }, .{ 0, 1, 0 }, 3, .all)) == null);
        try testing.expectError(error.InvalidFrameDelta, first.advance(-1));
    }
}

test "falling and rotating body collides with floor and synchronizes a scene root" {
    var registry = scene.Registry.init(testing.allocator);
    defer registry.deinit();
    var world = try physics.World.init(testing.allocator);
    defer world.deinit();

    const floor = try world.createBody(.{ .collider = .{ .box = .{ 5, 0.25, 5 } }, .pose = .{ .position = .{ 0, -0.25, 0 } } });
    const body = try world.createBody(.{
        .collider = .{ .box = .{ 0.5, 0.5, 0.5 } },
        .layer = .dynamic,
        .pose = .{ .position = .{ 0, 3, 0 } },
        .angular_velocity = .{ 0, 2, 0 },
    });
    const entity = try registry.create();
    try registry.add(entity, Transform{ .scale = @splat(0.5) });
    const child = try registry.create();
    try registry.add(child, Transform{ .position = .{ 0, 2, 0 } });
    try registry.setParent(child, entity);
    try testing.expectError(error.InvalidBodyEntity, world.bindEntity(body, &registry, child));
    try world.bindEntity(body, &registry, entity);

    _ = try world.advanceScene(&registry, 0);
    try testing.expectEqual(@as(f32, 3), registry.get(entity, Transform).?.position[1]);
    _ = try world.advanceScene(&registry, 0.05);
    const falling = try world.bodyState(body);
    try testing.expect(falling.velocity[1] < 0);
    try testing.expect(falling.pose.rotation.y > 0);

    for (0..180) |_| _ = try world.advanceScene(&registry, physics.fixed_delta);
    const resting = try world.bodyState(body);
    const local = registry.get(entity, Transform).?;
    try testing.expectApproxEqAbs(@as(f32, 0.5), resting.pose.position[1], 0.03);
    try testing.expectApproxEqAbs(@as(f32, 0), resting.velocity[1], 0.02);
    try testing.expectEqual(resting.pose.position, local.position);
    try testing.expectEqual(resting.pose.rotation, local.rotation);
    try testing.expectEqual([3]f32{ 0.5, 0.5, 0.5 }, local.scale);
    try testing.expectApproxEqAbs(@as(f32, 1.5), (try registry.worldMatrix(child)).?.rows[1][3], 0.05);

    const hit = (try world.raycast(.{ 0, 4, 0 }, .{ 0, -4, 0 }, 5, .all)).?;
    try testing.expectEqual(body, hit.body);
    try testing.expectEqual(entity, hit.entity.?);
    try testing.expectEqual(physics.Layer.dynamic, hit.layer);
    try testing.expectApproxEqAbs(@as(f32, 3), hit.distance, 0.05);
    try testing.expectApproxEqAbs(@as(f32, 1), hit.normal[1], 0.02);
    const floor_hit = (try world.raycast(.{ 0, 4, 0 }, .{ 0, -1, 0 }, 5, .{ .static = true })).?;
    try testing.expectEqual(floor, floor_hit.body);
    try testing.expectApproxEqAbs(@as(f32, 4), floor_hit.distance, 0.02);
    try testing.expect((try world.raycast(.{ 0, 4, 0 }, .{ 0, -1, 0 }, 2, .all)) == null);
    try testing.expectError(error.InvalidRay, world.raycast(.{ 0, 4, 0 }, .{ 0, 0, 0 }, 5, .all));

    try registry.destroy(entity);
    const reused = try registry.create();
    try registry.add(reused, Transform{});
    try testing.expectEqual(entity.index, reused.index);
    _ = try world.advanceScene(&registry, 0);
    try testing.expectEqual(@as(usize, 1), world.bodyCount());
    try testing.expectError(error.InvalidBody, world.bodyState(body));
    try testing.expectError(error.InvalidBody, world.destroyBody(body));
    try testing.expectEqual(Transform{}, registry.get(reused, Transform).?);
    try testing.expect((try world.raycast(.{ 0, 4, 0 }, .{ 0, -1, 0 }, 5, .{ .dynamic = true })) == null);
    try world.destroyBody(floor);
    try testing.expectEqual(@as(usize, 0), world.bodyCount());
}

test "static triangle mesh, sphere and capsule use the same filtered query" {
    var world = try physics.World.init(testing.allocator);
    defer world.deinit();
    const vertices = &.{
        [3]f32{ -5, 0, -5 }, [3]f32{ -5, 0, 5 }, [3]f32{ 5, 0, 5 }, [3]f32{ 5, 0, -5 },
    };
    const mesh: physics.Collider = .{ .mesh = .{ .vertices = vertices, .indices = &.{ 0, 1, 2, 0, 2, 3 } } };
    const ground = try world.createBody(.{ .collider = mesh });
    try testing.expectError(error.DynamicTriangleMesh, world.createBody(.{ .collider = mesh, .layer = .dynamic }));
    try testing.expectError(error.InvalidCollider, world.createBody(.{ .collider = .{ .sphere = -1 } }));
    const sphere = try world.createBody(.{ .collider = .{ .sphere = 0.5 }, .layer = .dynamic, .pose = .{ .position = .{ -2, 2, 0 } } });
    const capsule = try world.createBody(.{
        .collider = .{ .capsule = .{ .half_height = 0.6, .radius = 0.4 } },
        .layer = .dynamic,
        .pose = .{ .position = .{ 2, 2, 0 } },
    });
    for (0..120) |_| _ = try world.advance(physics.fixed_delta);
    try testing.expectApproxEqAbs(@as(f32, 0.5), (try world.bodyState(sphere)).pose.position[1], 0.03);
    try testing.expectApproxEqAbs(@as(f32, 1), (try world.bodyState(capsule)).pose.position[1], 0.03);
    const hit = (try world.raycast(.{ 1, 2, 0 }, .{ 0, -1, 0 }, 3, .{ .static = true })).?;
    try testing.expectEqual(ground, hit.body);
    try testing.expectEqual([3]f32{ 1, 0, 0 }, hit.position);
    try testing.expectEqual([3]f32{ 0, 1, 0 }, hit.normal);
}
