//! A training robot patrols, pursues the last visible player position and attacks in reach.
const Vec3 = @import("../scene/transform.zig").Vec3;
const physics = @import("../physics/world.zig");
const navigation = @import("waypoints.zig");

pub const Enemy = struct {
    pub const State = enum(u32) { patrol, chase, attack, down };
    pub const damage = 20;
    pub const half: Vec3 = .{ 0.36, 0.9, 0.36 };
    const reach = 1.65;

    feet: Vec3,
    state: State = .patrol,
    patrol_index: usize = 1,
    last_seen: ?Vec3 = null,
    attack_remaining: f32 = 0,

    pub fn center(self: Enemy) Vec3 {
        return .{ self.feet[0], self.feet[1] + half[1], self.feet[2] };
    }

    /// Returns one attack after a continuous, unobstructed wind-up.
    pub fn update(self: *Enemy, world: *const physics.World, body: physics.BodyId, dt: f32, player_feet: Vec3, graph: *const navigation.Graph, patrol: []const Vec3) !bool {
        if (dt <= 0 or self.state == .down) return false;
        const eye: Vec3 = .{ self.feet[0], self.feet[1] + 1.25, self.feet[2] };
        const toward: @Vector(3, f32) = .{
            player_feet[0] - eye[0],
            player_feet[1] + 0.95 - eye[1],
            player_feet[2] - eye[2],
        };
        const distance = @sqrt(@reduce(.Add, toward * toward));
        const visible = distance <= 8.5 and (distance == 0 or
            try world.raycastIgnoring(eye, toward, distance, .all, body) == null);
        if (visible) self.last_seen = player_feet;
        if (visible and distance <= reach) {
            if (self.state != .attack) self.attack_remaining = 0.45;
            self.state = .attack;
            self.attack_remaining -= dt;
            if (self.attack_remaining > 0) return false;
            self.attack_remaining += 0.8;
            return true;
        }
        if (!visible) {
            if (self.last_seen) |seen| {
                if (navigation.distance(self.feet, seen) <= 0.1 or graph.next(self.feet, seen) == null)
                    self.last_seen = null;
            }
        }
        self.state = if (self.last_seen != null) .chase else .patrol;
        if (self.state == .patrol and navigation.distance(self.feet, patrol[self.patrol_index]) <= 0.06)
            self.patrol_index = (self.patrol_index + 1) % patrol.len;
        const goal = self.last_seen orelse patrol[self.patrol_index];
        const hop = graph.next(self.feet, goal) orelse return false;
        const length = navigation.distance(self.feet, hop);
        if (length <= 0.0001) return false;
        const speed: f32 = if (self.state == .chase) 2.85 else 1.45;
        // Leave space for the player's capsule even when the player is airborne.
        const limit = if (visible) navigation.distance(self.feet, player_feet) - 0.8 else length;
        const fraction = @min(length, @min(@max(0, limit), dt * speed)) / length;
        self.feet[0] += (hop[0] - self.feet[0]) * fraction;
        self.feet[2] += (hop[2] - self.feet[2]) * fraction;
        return false;
    }
};
