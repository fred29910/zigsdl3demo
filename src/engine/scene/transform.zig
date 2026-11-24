const std = @import("std");

pub const Vec3 = [3]f32;

/// Unit quaternion, with the scalar component last.
pub const Rotation = struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,
    w: f32 = 1,

    pub fn axisAngle(unit_axis: Vec3, radians: f32) Rotation {
        const s = @sin(radians * 0.5);
        return .{ .x = unit_axis[0] * s, .y = unit_axis[1] * s, .z = unit_axis[2] * s, .w = @cos(radians * 0.5) };
    }

    /// Compose rotations, applying local first.
    pub fn mul(self: Rotation, local: Rotation) Rotation {
        return .{
            .x = self.w * local.x + self.x * local.w + self.y * local.z - self.z * local.y,
            .y = self.w * local.y - self.x * local.z + self.y * local.w + self.z * local.x,
            .z = self.w * local.z + self.x * local.y - self.y * local.x + self.z * local.w,
            .w = self.w * local.w - self.x * local.x - self.y * local.y - self.z * local.z,
        };
    }
};

/// Local transform, applied as translation * rotation * scale.
pub const Transform = struct {
    position: Vec3 = .{ 0, 0, 0 },
    rotation: Rotation = .{},
    scale: Vec3 = .{ 1, 1, 1 },
    /// Imported local affine matrix, when the asset supplies a matrix.
    local_matrix: ?Matrix = null,

    pub fn matrix(self: Transform) Matrix {
        if (self.local_matrix) |authored| return authored;
        const x, const y, const z, const w = .{ self.rotation.x, self.rotation.y, self.rotation.z, self.rotation.w };
        const sx, const sy, const sz = self.scale;
        const tx, const ty, const tz = self.position;
        return .{ .rows = .{
            .{ (1 - 2 * (y * y + z * z)) * sx, 2 * (x * y - z * w) * sy, 2 * (x * z + y * w) * sz, tx },
            .{ 2 * (x * y + z * w) * sx, (1 - 2 * (x * x + z * z)) * sy, 2 * (y * z - x * w) * sz, ty },
            .{ 2 * (x * z - y * w) * sx, 2 * (y * z + x * w) * sy, (1 - 2 * (x * x + y * y)) * sz, tz },
        } };
    }
};

/// Row-major affine matrix with an implicit final row of (0, 0, 0, 1).
pub const Matrix = extern struct {
    rows: [3][4]f32,

    pub fn mul(self: Matrix, local: Matrix) Matrix {
        var out: Matrix = undefined;
        for (self.rows, &out.rows) |a, *row| {
            for (row, 0..) |*element, col| {
                element.* = a[0] * local.rows[0][col] + a[1] * local.rows[1][col] + a[2] * local.rows[2][col];
            }
            row[3] += a[3];
        }
        return out;
    }
};

test "TRS scales before rotation and retains translation" {
    const transform: Transform = .{
        .position = .{ 4, 5, 6 },
        .rotation = Rotation.axisAngle(.{ 0, 1, 0 }, std.math.pi / 2.0),
        .scale = .{ 2, 3, 4 },
    };
    const rows = transform.matrix().rows;
    try std.testing.expectApproxEqAbs(@as(f32, -2), rows[2][0], 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 3), rows[1][1], 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 4), rows[0][2], 0.00001);
    try std.testing.expectEqual(@as(f32, 4), rows[0][3]);
    try std.testing.expectEqual(@as(f32, 5), rows[1][3]);
    try std.testing.expectEqual(@as(f32, 6), rows[2][3]);
}
