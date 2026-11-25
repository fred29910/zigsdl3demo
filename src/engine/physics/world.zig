//! Fixed-step rigid body and player simulation. The native Jolt API is private to this module.
const std = @import("std");
const native = @import("jolt_c");
const scene = @import("../scene/registry.zig");
const transform = @import("../scene/transform.zig");

const Vec3 = transform.Vec3;
const Rotation = transform.Rotation;

pub const BodyId = enum(u64) { _ };
pub const Layer = enum(u1) { static = native.PHYSICS_STATIC, dynamic = native.PHYSICS_DYNAMIC };
pub const Layers = packed struct(u32) {
    static: bool = false,
    dynamic: bool = false,
    reserved: u30 = 0,

    pub const all: Layers = .{ .static = true, .dynamic = true };
};

pub const Collider = union(enum) {
    box: Vec3, // half extents
    sphere: f32, // radius
    capsule: struct { radius: f32, half_height: f32 }, // cylindrical half-height along Y
    mesh: struct { vertices: []const Vec3, indices: []const u32 }, // static, local-space triangles
};

pub const Pose = struct {
    position: Vec3 = @splat(0),
    rotation: Rotation = .{},
};

pub const BodyDesc = struct {
    collider: Collider,
    layer: Layer = .static,
    pose: Pose = .{},
    velocity: Vec3 = @splat(0),
    angular_velocity: Vec3 = @splat(0),
};

pub const BodyState = struct {
    pose: Pose,
    velocity: Vec3,
    angular_velocity: Vec3,
    active: bool,
};

pub const RayHit = struct {
    body: BodyId,
    entity: ?scene.Entity,
    layer: Layer,
    position: Vec3,
    normal: Vec3,
    distance: f32,
};

pub const CharacterState = struct {
    feet: Vec3,
    grounded: bool,
};

pub const CharacterInput = struct {
    strafe: f32 = 0,
    forward: f32 = 0,
    yaw: f32 = 0,
    sprint: bool = false,
    jump_pressed: bool = false,
};

pub const fixed_delta: f32 = @floatCast(fixed_interval);
const fixed_interval: f64 = 1.0 / 60.0;
const max_steps = 6;
const max_frame_delta = max_steps * fixed_interval;

/// A world is owned by one simulation thread. IDs are local to the world.
pub const World = struct {
    allocator: std.mem.Allocator,
    handle: *native.PhysicsWorld,
    bodies: std.AutoArrayHashMapUnmanaged(BodyId, Entry) = .empty,
    next_id: u64 = 1,
    accumulated: f64 = 0,
    character: ?CharacterDrive = null,

    const CharacterDrive = struct {
        velocity: [2]f32 = @splat(0),
        jump_pending: bool = false,
    };

    const Entry = struct {
        native_id: u32,
        layer: Layer,
        entity: ?scene.Entity = null,
    };

    pub fn init(allocator: std.mem.Allocator) !World {
        return .{ .allocator = allocator, .handle = native.physics_world_create() orelse return error.PhysicsInit };
    }

    pub fn deinit(self: *World) void {
        for (self.bodies.values()) |entry| native.physics_body_destroy(self.handle, entry.native_id);
        self.bodies.deinit(self.allocator);
        native.physics_world_destroy(self.handle);
        self.* = undefined;
    }

    pub fn bodyCount(self: *const World) usize {
        return self.bodies.count();
    }

    /// Creates the local player. Feet are the capsule's bottom in world space.
    pub fn createCharacter(self: *World, feet: Vec3, radius: f32, half_height: f32) !void {
        if (self.character != null) return error.CharacterAlreadyExists;
        if (!finite(feet) or !validExtent(radius) or !validExtent(half_height) or
            !std.math.isFinite(2 * (radius + half_height))) return error.InvalidCharacter;
        if (!native.physics_character_create(self.handle, pack(feet), radius, half_height)) return error.CharacterCreationFailed;
        self.character = .{};
    }

    /// Submit frame input before advancing the world. A press survives frames
    /// without a physics tick. Null cancels input when mouse capture is lost.
    pub fn setCharacterInput(self: *World, input: ?CharacterInput) !void {
        const drive = if (self.character) |*value| value else return error.NoCharacter;
        const controls = input orelse {
            drive.* = .{};
            return;
        };
        if (!std.math.isFinite(controls.strafe) or !std.math.isFinite(controls.forward) or
            !std.math.isFinite(controls.yaw)) return error.InvalidCharacterInput;
        const x = std.math.clamp(controls.strafe, -1, 1);
        const z = std.math.clamp(controls.forward, -1, 1);
        const speed: f32 = if (controls.sprint) 7 else 3;
        const scale = speed / @max(1, @sqrt(x * x + z * z));
        const sin = @sin(controls.yaw);
        const cos = @cos(controls.yaw);
        drive.velocity = .{ (x * cos + z * sin) * scale, (z * cos - x * sin) * scale };
        drive.jump_pending = drive.jump_pending or controls.jump_pressed;
    }

    pub fn characterState(self: *const World) ?CharacterState {
        if (self.character == null) return null;
        const state = native.physics_character_state(self.handle);
        return .{ .feet = unpack(state.feet), .grounded = state.grounded };
    }

    /// Mesh data is only borrowed for this call. Jolt owns the cooked shape.
    pub fn createBody(self: *World, desc: BodyDesc) !BodyId {
        if (!finite(desc.pose.position) or !finite(desc.velocity) or !finite(desc.angular_velocity))
            return error.InvalidBodyState;
        const q = desc.pose.rotation;
        const length_squared = q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w;
        if (!std.math.isFinite(length_squared) or @abs(length_squared - 1) > 0.0001)
            return error.InvalidRotation;
        const inv_length = 1 / @sqrt(length_squared);
        if (self.next_id == std.math.maxInt(u64)) return error.BodyIdLimit;

        var settings: native.PhysicsBodyDesc = .{
            .pose = .{ .position = pack(desc.pose.position), .rotation = .{
                q.x * inv_length, q.y * inv_length, q.z * inv_length, q.w * inv_length,
            } },
            .velocity = pack(desc.velocity),
            .angular_velocity = pack(desc.angular_velocity),
            .user_data = self.next_id,
            .layer = @backingInt(desc.layer),
            .shape = undefined,
            .size = pack(.{ 0, 0, 0 }),
            .vertices = null,
            .indices = null,
            .vertex_count = 0,
            .index_count = 0,
        };
        switch (desc.collider) {
            .box => |half| {
                if (!validExtent(half[0]) or !validExtent(half[1]) or !validExtent(half[2])) return error.InvalidCollider;
                settings.shape = native.PHYSICS_BOX;
                settings.size = pack(half);
            },
            .sphere => |radius| {
                if (!validExtent(radius)) return error.InvalidCollider;
                settings.shape = native.PHYSICS_SPHERE;
                settings.size.x = radius;
            },
            .capsule => |capsule| {
                if (!validExtent(capsule.radius) or !validExtent(capsule.half_height)) return error.InvalidCollider;
                settings.shape = native.PHYSICS_CAPSULE;
                settings.size.x = capsule.radius;
                settings.size.y = capsule.half_height;
            },
            .mesh => |mesh| {
                if (desc.layer != .static) return error.DynamicTriangleMesh;
                if (mesh.vertices.len < 3 or mesh.vertices.len > std.math.maxInt(u32) or
                    mesh.indices.len == 0 or mesh.indices.len > std.math.maxInt(u32) or mesh.indices.len % 3 != 0)
                    return error.InvalidCollider;
                for (mesh.vertices) |v| if (!finite(v)) return error.InvalidCollider;
                for (mesh.indices) |i| if (i >= mesh.vertices.len) return error.InvalidCollider;
                comptime {
                    std.debug.assert(@sizeOf(Vec3) == @sizeOf(native.PhysicsVec3));
                    std.debug.assert(@alignOf(Vec3) == @alignOf(native.PhysicsVec3));
                }
                settings.shape = native.PHYSICS_MESH;
                settings.vertices = @ptrCast(mesh.vertices.ptr);
                settings.indices = mesh.indices.ptr;
                settings.vertex_count = mesh.vertices.len;
                settings.index_count = mesh.indices.len;
            },
        }
        try self.bodies.ensureUnusedCapacity(self.allocator, 1);
        var native_id: u32 = undefined;
        if (!native.physics_body_create(self.handle, &settings, &native_id)) return error.BodyCreationFailed;
        const id: BodyId = @fromBackingInt(@intCast(self.next_id));
        self.next_id += 1;
        self.bodies.putAssumeCapacityNoClobber(id, .{ .native_id = native_id, .layer = desc.layer });
        return id;
    }

    pub fn destroyBody(self: *World, id: BodyId) !void {
        const entry = self.bodies.fetchSwapRemove(id) orelse return error.InvalidBody;
        native.physics_body_destroy(self.handle, entry.value.native_id);
    }

    pub fn bodyState(self: *const World, id: BodyId) !BodyState {
        return self.readState(self.bodies.get(id) orelse return error.InvalidBody);
    }

    /// All bindings in a world belong to the same registry. Dynamic bodies are
    /// authoritative for position and rotation of root TRS entities.
    pub fn bindEntity(self: *World, id: BodyId, registry: *const scene.Registry, entity: scene.Entity) !void {
        const entry = self.bodies.getPtr(id) orelse return error.InvalidBody;
        if (entry.entity != null) return error.BodyAlreadyBound;
        if (!canBind(registry, entity, entry.layer)) return error.InvalidBodyEntity;
        for (self.bodies.values()) |other| {
            if (other.entity) |bound| {
                if (std.meta.eql(bound, entity)) return error.EntityAlreadyBound;
            }
        }
        entry.entity = entity;
    }

    pub fn advance(self: *World, dt: f32) !u32 {
        if (!std.math.isFinite(dt) or dt < 0) return error.InvalidFrameDelta;
        self.accumulated += @min(@as(f64, dt), max_frame_delta);
        var steps: u32 = 0;
        while (steps < max_steps and self.accumulated >= fixed_interval) : (steps += 1) {
            self.accumulated -= fixed_interval;
            if (self.character) |*drive| {
                native.physics_character_step(self.handle, fixed_delta, drive.velocity[0], drive.velocity[1], drive.jump_pending);
                drive.jump_pending = false;
            }
            if (native.physics_world_step(self.handle, fixed_delta) != 0) return error.PhysicsCapacityExceeded;
        }
        return steps;
    }

    /// Remove stale bindings before stepping. Copy only body pose back to the
    /// registry so render scale and child transforms remain scene-owned.
    pub fn advanceScene(self: *World, registry: *scene.Registry, dt: f32) !u32 {
        var i: usize = 0;
        while (i < self.bodies.count()) {
            const entry = self.bodies.values()[i];
            if (entry.entity) |entity| {
                if (!canBind(registry, entity, entry.layer)) {
                    try self.destroyBody(self.bodies.keys()[i]);
                    continue;
                }
            }
            i += 1;
        }
        const steps = try self.advance(dt);
        for (self.bodies.values()) |entry| {
            if (entry.layer != .dynamic) continue;
            const entity = entry.entity orelse continue;
            const pose = self.readState(entry).pose;
            var local = registry.get(entity, transform.Transform).?;
            if (std.meta.eql(local.position, pose.position) and std.meta.eql(local.rotation, pose.rotation)) continue;
            local.position = pose.position;
            local.rotation = pose.rotation;
            try registry.add(entity, local);
        }
        return steps;
    }

    /// direction can be any nonzero vector. Returns the closest hit within
    /// max_distance in world units, filtered by object layer.
    pub fn raycast(self: *const World, origin: Vec3, direction: Vec3, max_distance: f32, layers: Layers) !?RayHit {
        if (!finite(origin) or !finite(direction) or !validExtent(max_distance)) return error.InvalidRay;
        const magnitude = @max(@abs(direction[0]), @abs(direction[1]), @abs(direction[2]));
        if (magnitude == 0) return error.InvalidRay;
        const scaled = @as(@Vector(3, f32), direction) / @as(@Vector(3, f32), @splat(magnitude));
        const length = @sqrt(@reduce(.Add, scaled * scaled));
        const displacement: Vec3 = (scaled / @as(@Vector(3, f32), @splat(length))) * @as(@Vector(3, f32), @splat(max_distance));
        const end: Vec3 = @as(@Vector(3, f32), origin) + @as(@Vector(3, f32), displacement);
        if (!finite(end)) return error.InvalidRay;

        var hit: native.PhysicsRayHit = undefined;
        if (!native.physics_raycast(self.handle, pack(origin), pack(displacement), @bitCast(layers), &hit))
            return null;
        const id: BodyId = @fromBackingInt(@intCast(hit.user_data));
        const entry = self.bodies.get(id) orelse return error.UnmappedPhysicsBody;
        return .{
            .body = id,
            .entity = entry.entity,
            .layer = entry.layer,
            .position = unpack(hit.position),
            .normal = unpack(hit.normal),
            .distance = hit.fraction * max_distance,
        };
    }

    fn readState(self: *const World, entry: Entry) BodyState {
        var out: native.PhysicsBodyState = undefined;
        native.physics_body_state(self.handle, entry.native_id, &out);
        const x, const y, const z, const w = out.pose.rotation;
        return .{
            .pose = .{ .position = unpack(out.pose.position), .rotation = .{ .x = x, .y = y, .z = z, .w = w } },
            .velocity = unpack(out.velocity),
            .angular_velocity = unpack(out.angular_velocity),
            .active = out.active,
        };
    }
};

fn canBind(registry: *const scene.Registry, entity: scene.Entity, layer: Layer) bool {
    const local = registry.get(entity, transform.Transform) orelse return false;
    return layer == .static or (registry.getParent(entity) == null and local.local_matrix == null);
}

fn pack(v: Vec3) native.PhysicsVec3 {
    return .{ .x = v[0], .y = v[1], .z = v[2] };
}

fn unpack(v: native.PhysicsVec3) Vec3 {
    return .{ v.x, v.y, v.z };
}

fn finite(v: Vec3) bool {
    return std.math.isFinite(v[0]) and std.math.isFinite(v[1]) and std.math.isFinite(v[2]);
}

fn validExtent(value: f32) bool {
    return value > 0 and std.math.isFinite(value);
}
