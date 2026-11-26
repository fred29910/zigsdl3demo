const std = @import("std");
const InputState = @import("engine.platform.sdl").InputState;

const Vec3 = @Vector(3, f32);

/// Left-handed camera with +Y up and +Z forward at zero yaw and pitch.
pub const Camera = struct {
    position: Vec3 = .{ 0, 0, -5 },
    yaw: f32 = 0,
    pitch: f32 = 0,
    sensitivity: f32 = 0.0025,

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

    /// 仅在鼠标捕获时响应位移；未捕获时忽略本帧所有鼠标增量。
    pub fn look(self: *Camera, input: *const InputState, captured: bool) void {
        if (!captured) return;
        const delta = input.mouseDelta();
        self.yaw = @mod(self.yaw + delta.x * self.sensitivity, 2.0 * std.math.pi);
        self.pitch = std.math.clamp(self.pitch - delta.y * self.sensitivity, -1.55, 1.55);
    }

    pub fn setSensitivityFromUi(self: *Camera, multiplier: f32) void {
        const clamped = std.math.clamp(multiplier, 0.5, 2.0);
        self.sensitivity = 0.0025 * clamped;
    }

    /// 回合重开时只恢复默认视角与位置，保留会话灵敏度（FR-003）。
    pub fn resetForRound(self: *Camera) void {
        const sensitivity = self.sensitivity;
        self.* = .{ .sensitivity = sensitivity };
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

test "camera sensitivity default and UI mapping" {
    var cam = Camera{};
    try std.testing.expectApproxEqAbs(@as(f32, 0.0025), cam.sensitivity, 0.000001);
    cam.setSensitivityFromUi(2.0);
    try std.testing.expectApproxEqAbs(@as(f32, 0.005), cam.sensitivity, 0.000001);

    cam.setSensitivityFromUi(0.1);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0025 * 0.5), cam.sensitivity, 0.000001);
    cam.setSensitivityFromUi(5.0);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0025 * 2.0), cam.sensitivity, 0.000001);

    var input = InputState.init();
    input.mouse_dx = 10;
    input.mouse_dy = 4;
    var c1 = Camera{};
    var c2 = Camera{};
    c2.setSensitivityFromUi(2.0);
    const yaw0_1 = c1.yaw;
    const yaw0_2 = c2.yaw;
    c1.look(&input, true);
    c2.look(&input, true);
    const inc1 = c1.yaw - yaw0_1;
    const inc2 = c2.yaw - yaw0_2;
    try std.testing.expectApproxEqAbs(inc1 * 2.0, inc2, 0.0001);
}

test "perspective maps near and far planes to the SDL depth range" {
    const p = (Camera{}).uniforms(2).projection;
    try std.testing.expectApproxEqAbs(p[1], p[0] * 2, 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), (0.1 * p[2] + p[3]) / 0.1, 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 1), (100 * p[2] + p[3]) / 100, 0.00001);
}

test "mouse look requires capture and keeps pitch within limits" {
    var cam = Camera{};
    var input = InputState.init();
    input.mouse_dx = 30;
    input.mouse_dy = -20;

    // 未捕获时忽略本帧位移，视角保持不变。
    cam.look(&input, false);
    try std.testing.expectEqual(@as(f32, 0), cam.yaw);
    try std.testing.expectEqual(@as(f32, 0), cam.pitch);

    cam.look(&input, true);
    try std.testing.expect(cam.yaw > 0);
    try std.testing.expect(cam.pitch > 0);
    try std.testing.expect(cam.direction()[1] > 0);

    var extreme = InputState.init();
    extreme.mouse_dy = -100000;
    for (0..10) |_| cam.look(&extreme, true);
    try std.testing.expect(cam.pitch <= 1.55);
    const top_pitch = cam.pitch;
    cam.look(&extreme, true);
    try std.testing.expectEqual(top_pitch, cam.pitch);
    extreme.mouse_dy = 100000;
    for (0..10) |_| cam.look(&extreme, true);
    try std.testing.expect(cam.pitch >= -1.55);
}

test "round reset keeps sensitivity and restores default view" {
    var cam = Camera{};
    cam.setSensitivityFromUi(2.0);
    cam.yaw = 1.2;
    cam.pitch = 0.7;
    cam.position = .{ 3, 4, 5 };

    cam.resetForRound();

    try std.testing.expectApproxEqAbs(@as(f32, 0.005), cam.sensitivity, 0.000001);
    try std.testing.expectEqual(@as(f32, 0), cam.yaw);
    try std.testing.expectEqual(@as(f32, 0), cam.pitch);
    try std.testing.expectEqual(@as(f32, -5), cam.position[2]);
}

test "sensitivity ratio 0.5 to 2.0 yields a fourfold yaw response" {
    var low = Camera{};
    var high = Camera{};
    low.setSensitivityFromUi(0.5);
    high.setSensitivityFromUi(2.0);
    var input = InputState.init();
    input.mouse_dx = 100;
    low.look(&input, true);
    high.look(&input, true);
    try std.testing.expect(low.yaw > 0);
    try std.testing.expectApproxEqAbs(low.yaw * 4.0, high.yaw, 0.0001);
}
