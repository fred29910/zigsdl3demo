const std = @import("std");
const InputState = @import("engine.platform.sdl").InputState;

const Vec3 = @Vector(3, f32);

/// Left-handed camera with +Y up and +Z forward at zero yaw and pitch.
pub const Camera = struct {
    position: Vec3 = .{ 0, 0, -5 },
    yaw: f32 = 0,
    pitch: f32 = 0,

    pub const Uniforms = extern struct {
        eye: [4]f32,
        right: [4]f32,
        up: [4]f32,
        forward: [4]f32,
        projection: [4]f32,
    };

    fn basis(self: Camera) struct { right: Vec3, up: Vec3, forward: Vec3 } {
        const sy = @sin(self.yaw);
        const cy = @cos(self.yaw);
        const sp = @sin(self.pitch);
        const cp = @cos(self.pitch);
        return .{
            .right = .{ cy, 0, -sy },
            .up = .{ -sy * sp, cp, -cy * sp },
            .forward = .{ sy * cp, sp, cy * cp },
        };
    }

    pub fn look(self: *Camera, input: *const InputState) void {
        const delta = input.mouseDelta();
        self.yaw = @mod(self.yaw + delta.x * 0.0025, 2.0 * std.math.pi);
        self.pitch = std.math.clamp(self.pitch - delta.y * 0.0025, -1.55, 1.55);
    }

    pub fn fly(self: *Camera, input: *const InputState, dt: f32) void {
        const axes = self.basis();
        var movement: Vec3 = @splat(0);
        if (input.isDown(.move_forward)) movement += axes.forward;
        if (input.isDown(.move_back)) movement -= axes.forward;
        if (input.isDown(.move_right)) movement += axes.right;
        if (input.isDown(.move_left)) movement -= axes.right;
        if (input.isDown(.jump)) movement += Vec3{ 0, 1, 0 };
        if (input.isDown(.crouch)) movement -= Vec3{ 0, 1, 0 };
        const magnitude = @sqrt(@reduce(.Add, movement * movement));
        if (magnitude > 0) {
            const speed: f32 = if (input.isDown(.sprint)) 7 else 3;
            self.position += movement * @as(Vec3, @splat(speed * dt / magnitude));
        }
    }

    pub fn direction(self: Camera) [3]f32 {
        return self.basis().forward;
    }

    pub fn uniforms(self: Camera, aspect: f32) Uniforms {
        const axes = self.basis();
        const f = 1.0 / @tan(std.math.pi / 6.0);
        const near = 0.1;
        const far = 100.0;
        return .{
            .eye = pack(self.position),
            .right = pack(axes.right),
            .up = pack(axes.up),
            .forward = pack(axes.forward),
            .projection = .{ f / aspect, f, far / (far - near), -near * far / (far - near) },
        };
    }
};

fn pack(v: Vec3) [4]f32 {
    return .{ v[0], v[1], v[2], 0 };
}

test "perspective maps near and far planes to the SDL depth range" {
    const p = (Camera{}).uniforms(2).projection;
    try std.testing.expectApproxEqAbs(p[1], p[0] * 2, 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), (0.1 * p[2] + p[3]) / 0.1, 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 1), (100 * p[2] + p[3]) / 100, 0.00001);
}
