//! Directional light projection and GPU textures shared by the scene passes.
const std = @import("std");
const gpu = @import("sdl3").gpu;
const assets = @import("../assets/asset_manager.zig");
const Matrix = @import("../scene/transform.zig").Matrix;
const RenderItem = @import("render_queue.zig").RenderItem;

const Vec3 = @Vector(3, f32);
pub const shadow_size = 2048;
const sky_size = 64;
const sun = unit(.{ -0.5, 0.78, -0.38 });
const forward = -sun;
const right = unit(cross(.{ 0, 1, 0 }, forward));
const up = cross(forward, right);
const light_view: Matrix = .{ .rows = .{ pack(right, 0), pack(up, 0), pack(forward, 0) } };
const shadow_usage: gpu.TextureUsage = .{ .sampler = true, .depth_stencil_target = true };

pub const Uniforms = extern struct {
    eye: [4]f32,
    sun_and_texel: [4]f32 = pack(sun, 1.0 / @as(f32, shadow_size)),
    projection: Matrix,
};

pub const Environment = struct {
    shadow: *gpu.Texture,
    shadow_format: gpu.TextureFormat,
    shadow_sampler: *gpu.Sampler,
    sky: *gpu.Texture,
    sky_sampler: *gpu.Sampler,

    pub fn init(device: *gpu.Device) !Environment {
        const format: gpu.TextureFormat = for ([_]gpu.TextureFormat{ .d32_float, .d16_unorm }) |candidate| {
            if (device.supportsTextureFormat(candidate, .two_d, shadow_usage)) break candidate;
        } else return error.NoSampleableDepthFormat;
        const shadow = try device.createTexture(.{
            .format = format,
            .usage = shadow_usage,
            .width = shadow_size,
            .height = shadow_size,
        });
        errdefer device.releaseTexture(shadow);
        const shadow_sampler = try device.createSampler(.{
            .address_mode_u = .clamp_to_edge,
            .address_mode_v = .clamp_to_edge,
        });
        errdefer device.releaseSampler(shadow_sampler);
        const sky = try createSky(device);
        errdefer device.releaseTexture(sky);
        const sky_sampler = try device.createSampler(.{
            .min_filter = .linear,
            .mag_filter = .linear,
            .address_mode_u = .clamp_to_edge,
            .address_mode_v = .clamp_to_edge,
            .address_mode_w = .clamp_to_edge,
        });
        return .{
            .shadow = shadow,
            .shadow_format = format,
            .shadow_sampler = shadow_sampler,
            .sky = sky,
            .sky_sampler = sky_sampler,
        };
    }

    pub fn deinit(self: Environment, device: *gpu.Device) void {
        device.releaseSampler(self.sky_sampler);
        device.releaseTexture(self.sky);
        device.releaseSampler(self.shadow_sampler);
        device.releaseTexture(self.shadow);
    }
};

/// Fit an orthographic map to visible scene geometry in light space. Each
/// instance contributes its transformed local bounds, independent of the camera.
pub fn shadowProjection(manager: *const assets.AssetManager, items: []const RenderItem) Matrix {
    var bounds: assets.Bounds = .{};
    for (items) |item| {
        const mesh = manager.mesh(item.mesh) orelse continue;
        includeBounds(&bounds, mesh.bounds, light_view.mul(item.model));
    }
    if (bounds.min[0] > bounds.max[0]) return light_view;
    return fit(bounds);
}

fn includeBounds(out: *assets.Bounds, bounds: assets.Bounds, model_to_light: Matrix) void {
    const center = (bounds.min + bounds.max) * @as(Vec3, @splat(0.5));
    const half = (bounds.max - bounds.min) * @as(Vec3, @splat(0.5));
    var projected_center: Vec3 = undefined;
    var projected_half: Vec3 = undefined;
    inline for (model_to_light.rows, 0..) |row, axis| {
        const xyz: Vec3 = .{ row[0], row[1], row[2] };
        projected_center[axis] = dot(xyz, center) + row[3];
        projected_half[axis] = dot(@abs(xyz), half);
    }
    out.include(projected_center - projected_half);
    out.include(projected_center + projected_half);
}

fn fit(bounds: assets.Bounds) Matrix {
    const span = bounds.max - bounds.min;
    const pad = @max(span * @as(Vec3, @splat(0.05)), @as(Vec3, @splat(0.1)));
    const lo = bounds.min - pad;
    const hi = bounds.max + pad;
    const scale = Vec3{ 2, 2, 1 } / (hi - lo);
    const offset = -lo * scale - Vec3{ 1, 1, 0 };
    return .{ .rows = .{
        pack(right * @as(Vec3, @splat(scale[0])), offset[0]),
        pack(up * @as(Vec3, @splat(scale[1])), offset[1]),
        pack(forward * @as(Vec3, @splat(scale[2])), offset[2]),
    } };
}

fn createSky(device: *gpu.Device) !*gpu.Texture {
    const texture = try device.createTexture(.{
        .type = .cube,
        .format = .r8g8b8a8_unorm_srgb,
        .usage = .{ .sampler = true },
        .width = sky_size,
        .height = sky_size,
        .layer_count_or_depth = 6,
    });
    errdefer device.releaseTexture(texture);

    const face_bytes = sky_size * sky_size * 4;
    const transfer = try device.createTransferBuffer(.{ .size = face_bytes * 6 });
    defer device.releaseTransferBuffer(transfer);
    const memory = try device.mapTransferBuffer(transfer, face_bytes * 6, false);
    for (0..6) |layer| {
        for (0..sky_size) |y| for (0..sky_size) |x| {
            const u = (@as(f32, @floatFromInt(x)) + 0.5) * (2.0 / @as(f32, sky_size)) - 1;
            const v = (@as(f32, @floatFromInt(y)) + 0.5) * (2.0 / @as(f32, sky_size)) - 1;
            const offset = layer * face_bytes + (y * sky_size + x) * 4;
            memory[offset..][0..4].* = skyPixel(cubeRay(layer, u, v));
        };
    }
    device.unmapTransferBuffer(transfer);
    const commands = try device.acquireCommandBuffer();
    const copy = commands.beginCopyPass() catch |err| {
        commands.cancel() catch {};
        return err;
    };
    for (0..6) |layer| {
        copy.uploadToTexture(
            .{ .transfer_buffer = transfer, .offset = @intCast(layer * face_bytes) },
            .{ .texture = texture, .layer = @intCast(layer), .w = sky_size, .h = sky_size },
            false,
        );
    }
    copy.end();
    try commands.submit();
    return texture;
}

fn cubeRay(layer: usize, u: f32, v: f32) Vec3 {
    // SDL layer order +X, -X, +Y, -Y, +Z, -Z, with top-left texel origin.
    return unit(switch (layer) {
        0 => .{ 1, -v, -u },
        1 => .{ -1, -v, u },
        2 => .{ u, 1, v },
        3 => .{ u, -1, -v },
        4 => .{ u, -v, 1 },
        5 => .{ -u, -v, -1 },
        else => unreachable,
    });
}

fn skyPixel(ray: Vec3) [4]u8 {
    const horizon: Vec3 = .{ 188, 211, 223 };
    const pole: Vec3 = if (ray[1] >= 0) .{ 50, 109, 180 } else .{ 83, 94, 105 };
    const mix: Vec3 = @splat(@sqrt(@abs(ray[1])));
    const sun_amount: Vec3 = @splat(std.math.pow(f32, @max(dot(ray, sun), 0), 128));
    const color = @min(horizon + (pole - horizon) * mix + Vec3{ 125, 105, 85 } * sun_amount, @as(Vec3, @splat(255)));
    return .{ @intFromFloat(color[0]), @intFromFloat(color[1]), @intFromFloat(color[2]), 255 };
}

fn pack(v: Vec3, w: f32) [4]f32 {
    return .{ v[0], v[1], v[2], w };
}

fn dot(a: Vec3, b: Vec3) f32 {
    return @reduce(.Add, a * b);
}

fn unit(v: Vec3) Vec3 {
    return v / @as(Vec3, @splat(@sqrt(dot(v, v))));
}

fn cross(a: Vec3, b: Vec3) Vec3 {
    return .{ a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0] };
}

test "directional shadow fit contains reflected, scaled and flat instances" {
    const model: Matrix = .{ .rows = .{ .{ -3, 0, 0, 9 }, .{ 0, 1, 0, -4 }, .{ 0, 0.5, 2, 0 } } };
    var bounds: assets.Bounds = .{};
    includeBounds(&bounds, .{ .min = .{ -1, 0, -2 }, .max = .{ 1, 0, 2 } }, light_view.mul(model));
    const clip = fit(bounds).mul(model);
    for ([_]f32{ -1, 1 }) |x| for ([_]f32{ -2, 2 }) |z| {
        for (clip.rows, 0..) |row, axis| {
            const value = row[0] * x + row[2] * z + row[3];
            try std.testing.expect(value >= @as(f32, if (axis == 2) 0 else -1) and value <= 1);
        }
    };
}
