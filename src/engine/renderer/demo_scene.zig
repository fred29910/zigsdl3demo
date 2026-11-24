//! M3 scene and its GPU resources. The window and GPU device belong to GpuRenderer.
const std = @import("std");
const sdl = @import("sdl3");
const Logger = @import("zigsdl3demo").Logger;
const InputState = @import("engine.platform.sdl").InputState;
const GpuRenderer = @import("gpu_renderer.zig").GpuRenderer;
const Camera = @import("camera.zig").Camera;

const gpu = sdl.gpu;
const raw = sdl.raw;
const log = Logger.init(.info);
const texture_size = 32;
const depth_usage: gpu.TextureUsage = .{ .depth_stencil_target = true };

extern fn demo_imgui_init(window: *raw.SDL_Window, device: *raw.SDL_GPUDevice) bool;
extern fn demo_imgui_shutdown() void;
extern fn demo_imgui_event(event: *const raw.SDL_Event) void;
extern fn demo_imgui_prepare(commands: *raw.SDL_GPUCommandBuffer, ms: f32, captured: bool, speed: *f32) void;
extern fn demo_imgui_draw(commands: *raw.SDL_GPUCommandBuffer, pass: *raw.SDL_GPURenderPass) void;

pub const Scene = struct {
    device: *gpu.Device,
    pipeline: *gpu.GraphicsPipeline,
    vertices: *gpu.Buffer,
    indices: *gpu.Buffer,
    texture: *gpu.Texture,
    sampler: *gpu.Sampler,
    depth_format: gpu.TextureFormat,
    depth: ?*gpu.Texture = null,
    depth_extent: GpuRenderer.Extent = .{ .width = 0, .height = 0 },
    camera: Camera = .{},
    rotation: f32 = 0.45,
    rotation_speed: f32 = 0.85,

    pub fn init(renderer: GpuRenderer) !Scene {
        const device = renderer.device;
        const depth_format: gpu.TextureFormat = if (device.supportsTextureFormat(.d32_float, .two_d, depth_usage))
            .d32_float
        else if (device.supportsTextureFormat(.d16_unorm, .two_d, depth_usage))
            .d16_unorm
        else
            return error.NoDepthFormat;
        const pipeline = try createPipeline(device, device.swapchainTextureFormat(renderer.window), depth_format);
        errdefer device.releaseGraphicsPipeline(pipeline);
        const vertices = try device.createBuffer(.{ .usage = .{ .vertex = true }, .size = @sizeOf(@TypeOf(mesh_vertices)) });
        errdefer device.releaseBuffer(vertices);
        const indices = try device.createBuffer(.{ .usage = .{ .index = true }, .size = @sizeOf(@TypeOf(mesh_indices)) });
        errdefer device.releaseBuffer(indices);
        const texture = try device.createTexture(.{
            .format = .r8g8b8a8_unorm,
            .usage = .{ .sampler = true },
            .width = texture_size,
            .height = texture_size,
        });
        errdefer device.releaseTexture(texture);
        const sampler = try device.createSampler(.nearest_clamp);
        errdefer device.releaseSampler(sampler);
        try upload(device, vertices, indices, texture);
        if (!demo_imgui_init(renderer.window.handle, @ptrCast(device))) return error.ImGuiInit;
        log.log(.info, "scene", "纹理立方体、索引三角形和 ImGui 就绪，深度格式 {s}", .{@tagName(depth_format)});
        return .{
            .device = device,
            .pipeline = pipeline,
            .vertices = vertices,
            .indices = indices,
            .texture = texture,
            .sampler = sampler,
            .depth_format = depth_format,
        };
    }

    pub fn deinit(self: Scene) void {
        self.device.waitForIdle() catch {
            log.log(.warn, "scene", "等待 GPU 空闲失败: {s}", .{sdl.lastErrorText()});
        };
        demo_imgui_shutdown();
        if (self.depth) |depth| self.device.releaseTexture(depth);
        self.device.releaseSampler(self.sampler);
        self.device.releaseTexture(self.texture);
        self.device.releaseBuffer(self.indices);
        self.device.releaseBuffer(self.vertices);
        self.device.releaseGraphicsPipeline(self.pipeline);
    }

    pub fn processEvent(event: *const raw.SDL_Event) void {
        demo_imgui_event(event);
    }

    pub fn render(self: *Scene, renderer: GpuRenderer, input: *const InputState, dt: f32) !?GpuRenderer.Extent {
        const frame = (try renderer.acquireFrame()) orelse return null;
        const step = @min(dt, 0.05);
        const captured = input.mouseCaptured();
        if (captured) self.camera.update(input, step);
        self.rotation = @mod(self.rotation + step * self.rotation_speed, 200.0 * std.math.pi);

        self.record(frame, dt * 1000, captured) catch |err| {
            log.log(.error_, "scene", "录制场景命令失败: {s}", .{sdl.lastErrorText()});
            frame.submit() catch {};
            return err;
        };
        try frame.submit();
        return frame.extent;
    }

    fn record(self: *Scene, frame: GpuRenderer.Frame, frame_ms: f32, captured: bool) !void {
        const depth = try self.depthTarget(frame.extent);
        demo_imgui_prepare(@ptrCast(frame.commands), frame_ms, captured, &self.rotation_speed);
        const pass = try frame.commands.beginRenderPass(&.{frame.colorTarget(.clear)}, &.{
            .texture = depth,
            .load_op = .clear,
            .clear_depth = 1,
            .store_op = .dont_care,
            .stencil_load_op = .dont_care,
            .cycle = true,
        });
        const aspect = @as(f32, @floatFromInt(frame.extent.width)) / @as(f32, @floatFromInt(frame.extent.height));
        pass.bindGraphicsPipeline(self.pipeline);
        pass.bindVertexBuffers(0, &.{.{ .buffer = self.vertices }});
        pass.bindIndexBuffer(.{ .buffer = self.indices }, .u16);
        pass.bindFragmentSamplers(0, &.{.{ .texture = self.texture, .sampler = self.sampler }});
        frame.commands.pushVertexUniform(0, self.camera.uniforms(aspect, .{ 0, 0, 0, self.rotation }));
        pass.drawIndexedPrimitives(cube_index_count, 1, 0, 0, 0);
        // Draw the triangle second and behind the cube to demonstrate depth occlusion.
        frame.commands.pushVertexUniform(0, self.camera.uniforms(aspect, .{ -1.6, -0.35, 1.2, 0 }));
        pass.drawIndexedPrimitives(3, 1, cube_index_count, 0, 0);
        pass.end();

        const overlay = try frame.commands.beginRenderPass(&.{frame.colorTarget(.load)}, null);
        demo_imgui_draw(@ptrCast(frame.commands), @ptrCast(overlay));
        overlay.end();
    }

    fn depthTarget(self: *Scene, extent: GpuRenderer.Extent) !*gpu.Texture {
        if (self.depth) |depth| {
            if (std.meta.eql(self.depth_extent, extent)) return depth;
        }
        const replacement = try self.device.createTexture(.{
            .format = self.depth_format,
            .width = extent.width,
            .height = extent.height,
            .usage = depth_usage,
        });
        if (self.depth) |old| self.device.releaseTexture(old);
        self.depth = replacement;
        self.depth_extent = extent;
        return replacement;
    }
};

fn createPipeline(device: *gpu.Device, color: gpu.TextureFormat, depth: gpu.TextureFormat) !*gpu.GraphicsPipeline {
    // SDL's Vulkan backend expects SPIR-V bytes aligned for uint32_t.
    const vertex_code align(4) = @embedFile("demo.vert.spv").*;
    const fragment_code align(4) = @embedFile("demo.frag.spv").*;
    const vertex = try device.createShader(.{
        .code = &vertex_code,
        .code_size = vertex_code.len,
        .entrypoint = "main",
        .format = .{ .spirv = true },
        .stage = .vertex,
        .num_uniform_buffers = 1,
    });
    defer device.releaseShader(vertex);
    const fragment = try device.createShader(.{
        .code = &fragment_code,
        .code_size = fragment_code.len,
        .entrypoint = "main",
        .format = .{ .spirv = true },
        .stage = .fragment,
        .num_samplers = 1,
    });
    defer device.releaseShader(fragment);
    const targets = [_]gpu.ColorTargetDescription{.{ .format = color }};
    return device.createGraphicsPipeline(.{
        .vertex_shader = vertex,
        .fragment_shader = fragment,
        .vertex_input_state = .from(
            &.{.{ .pitch = @sizeOf(Vertex) }},
            &.{
                .{ .location = 0, .format = .float3, .offset = @offsetOf(Vertex, "position") },
                .{ .location = 1, .format = .float2, .offset = @offsetOf(Vertex, "uv") },
            },
        ),
        .rasterizer_state = .{ .enable_depth_clip = true },
        .depth_stencil_state = .{ .compare_op = .less, .enable_depth_test = true, .enable_depth_write = true },
        .target_info = .{
            .color_target_descriptions = &targets,
            .num_color_targets = targets.len,
            .has_depth_stencil_target = true,
            .depth_stencil_format = depth,
        },
    });
}

fn upload(device: *gpu.Device, vertices: *gpu.Buffer, indices: *gpu.Buffer, texture: *gpu.Texture) !void {
    const vertex_bytes = std.mem.asBytes(&mesh_vertices);
    const index_bytes = std.mem.asBytes(&mesh_indices);
    const index_offset: u32 = @sizeOf(@TypeOf(mesh_vertices));
    const texture_offset = std.mem.alignForward(u32, index_offset + @sizeOf(@TypeOf(mesh_indices)), 4);
    const transfer_size = texture_offset + @as(u32, @sizeOf(@TypeOf(pixels)));
    const transfer = try device.createTransferBuffer(.{ .size = transfer_size });
    defer device.releaseTransferBuffer(transfer);
    const memory = try device.mapTransferBuffer(transfer, transfer_size, false);
    @memcpy(memory[0..vertex_bytes.len], vertex_bytes);
    @memcpy(memory[index_offset..][0..index_bytes.len], index_bytes);
    @memcpy(memory[texture_offset..], &pixels);
    device.unmapTransferBuffer(transfer);

    const commands = try device.acquireCommandBuffer();
    const pass = commands.beginCopyPass() catch |err| {
        log.log(.error_, "scene", "上传 Copy Pass 失败: {s}", .{sdl.lastErrorText()});
        commands.cancel() catch {};
        return err;
    };
    pass.uploadToBuffer(.{ .transfer_buffer = transfer }, .{ .buffer = vertices, .size = index_offset }, false);
    pass.uploadToBuffer(
        .{ .transfer_buffer = transfer, .offset = index_offset },
        .{ .buffer = indices, .size = @sizeOf(@TypeOf(mesh_indices)) },
        false,
    );
    pass.uploadToTexture(
        .{ .transfer_buffer = transfer, .offset = texture_offset },
        .{ .texture = texture, .w = texture_size, .h = texture_size },
        false,
    );
    pass.end();
    try commands.submit();
}

const Vertex = extern struct { position: [3]f32, uv: [2]f32 };

fn face(a: [3]f32, b: [3]f32, c: [3]f32, d: [3]f32) [4]Vertex {
    return .{
        .{ .position = a, .uv = .{ 0, 1 } }, .{ .position = b, .uv = .{ 1, 1 } },
        .{ .position = c, .uv = .{ 1, 0 } }, .{ .position = d, .uv = .{ 0, 0 } },
    };
}

const mesh_vertices =
    face(.{ -1, -1, -1 }, .{ 1, -1, -1 }, .{ 1, 1, -1 }, .{ -1, 1, -1 }) ++
    face(.{ 1, -1, 1 }, .{ -1, -1, 1 }, .{ -1, 1, 1 }, .{ 1, 1, 1 }) ++
    face(.{ -1, -1, 1 }, .{ -1, -1, -1 }, .{ -1, 1, -1 }, .{ -1, 1, 1 }) ++
    face(.{ 1, -1, -1 }, .{ 1, -1, 1 }, .{ 1, 1, 1 }, .{ 1, 1, -1 }) ++
    face(.{ -1, 1, -1 }, .{ 1, 1, -1 }, .{ 1, 1, 1 }, .{ -1, 1, 1 }) ++
    face(.{ -1, -1, 1 }, .{ 1, -1, 1 }, .{ 1, -1, -1 }, .{ -1, -1, -1 }) ++
    [_]Vertex{
        .{ .position = .{ -0.85, -0.75, 0 }, .uv = .{ 0, 1 } },
        .{ .position = .{ 0.85, -0.75, 0 }, .uv = .{ 1, 1 } },
        .{ .position = .{ 0, 1, 0 }, .uv = .{ 0.5, 0 } },
    };

const cube_index_count = 36;
const mesh_indices = [_]u16{
    0,  1,  2,  0,  2,  3,  4,  5,  6,  4,  6,  7,
    8,  9,  10, 8,  10, 11, 12, 13, 14, 12, 14, 15,
    16, 17, 18, 16, 18, 19, 20, 21, 22, 20, 22, 23,
    24, 25, 26,
};

const pixels: [texture_size * texture_size * 4]u8 = blk: {
    @setEvalBranchQuota(4000);
    var data: [texture_size * texture_size * 4]u8 = undefined;
    for (0..texture_size) |y| {
        for (0..texture_size) |x| {
            const offset = (y * texture_size + x) * 4;
            data[offset..][0..4].* = if ((x / 4 + y / 4) % 2 == 0)
                .{ 241, 146, 59, 255 }
            else
                .{ 35, 92, 145, 255 };
        }
    }
    break :blk data;
};
