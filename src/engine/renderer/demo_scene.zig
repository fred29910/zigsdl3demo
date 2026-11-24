//! Demo scene and its GPU resources. The window and GPU device belong to GpuRenderer.
const std = @import("std");
const sdl = @import("sdl3");
const Logger = @import("zigsdl3demo").Logger;
const InputState = @import("engine.platform.sdl").InputState;
const GpuRenderer = @import("gpu_renderer.zig").GpuRenderer;
const Camera = @import("camera.zig").Camera;
const RenderQueue = @import("render_queue.zig").RenderQueue;
const RenderItem = @import("render_queue.zig").RenderItem;
const scene = @import("../scene/registry.zig");
const Instance = @import("../scene/model_instance.zig").Instance;
const transform = @import("../scene/transform.zig");
const assets = @import("../assets/asset_manager.zig");
const lighting = @import("lighting.zig");
const Vertex = @import("../assets/gltf.zig").Vertex;

const gpu = sdl.gpu;
const raw = sdl.raw;
const log = Logger.init(.info);
const depth_usage: gpu.TextureUsage = .{ .depth_stencil_target = true };

extern fn demo_imgui_init(window: *raw.SDL_Window, device: *raw.SDL_GPUDevice) bool;
extern fn demo_imgui_shutdown() void;
extern fn demo_imgui_event(event: *const raw.SDL_Event) void;
extern fn demo_imgui_prepare(commands: *raw.SDL_GPUCommandBuffer, ms: f32, captured: bool, speed: ?*f32, draw_count: usize) void;
extern fn demo_imgui_draw(commands: *raw.SDL_GPUCommandBuffer, pass: *raw.SDL_GPURenderPass) void;

const DrawUniforms = extern struct {
    camera: Camera.Uniforms,
    model: transform.Matrix,
};

const ShadowUniforms = extern struct {
    model: transform.Matrix,
    projection: transform.Matrix,
};

const SkyUniforms = extern struct {
    camera: Camera.Uniforms,
    flags: [4]f32,
};

const Pass = enum { lit, shadow, sky };

const MaterialUniforms = extern struct {
    base_color: [4]f32,
    flags: [4]f32,
    surface: [4]f32,
};

pub const DemoScene = struct {
    registry: scene.Registry,
    queue: RenderQueue,
    assets: assets.AssetManager,
    model: assets.ModelHandle,
    instance: Instance,
    spinning_cube: ?scene.Entity,
    spin_base: transform.Matrix,
    device: *gpu.Device,
    pipeline: *gpu.GraphicsPipeline,
    shadow_pipeline: *gpu.GraphicsPipeline,
    sky_pipeline: *gpu.GraphicsPipeline,
    environment: lighting.Environment,
    encode_srgb: f32,
    depth_format: gpu.TextureFormat,
    depth: ?*gpu.Texture = null,
    depth_extent: GpuRenderer.Extent = .{ .width = 0, .height = 0 },
    camera: Camera = .{},
    rotation: f32 = 0.45,
    rotation_speed: f32 = 0.85,

    pub fn init(renderer: GpuRenderer, allocator: std.mem.Allocator, io: std.Io, path: ?[]const u8) !DemoScene {
        var manager = try assets.AssetManager.init(allocator, renderer.device);
        errdefer manager.deinit();
        const model = loadSceneAsset(&manager, io, path) catch |err| {
            log.log(.error_, "assets", "加载 {s} 失败: {s}", .{ path orelse "demo.glb", @errorName(err) });
            return err;
        };
        // Retaining the same source a second time exercises the cache without duplicating GPU resources.
        const cached = try loadSceneAsset(&manager, io, path);
        try manager.releaseModel(cached);
        var registry = scene.Registry.init(allocator);
        errdefer registry.deinit();
        var instance = try Instance.init(&registry, &manager, model);
        errdefer instance.deinit(&registry);
        const spinning = if (path == null) instance.first_root else null;
        const spin_base = if (spinning) |entity| registry.get(entity, transform.Transform).?.matrix() else (transform.Transform{}).matrix();

        const device = renderer.device;
        const depth_format: gpu.TextureFormat = if (device.supportsTextureFormat(.d32_float, .two_d, depth_usage))
            .d32_float
        else if (device.supportsTextureFormat(.d16_unorm, .two_d, depth_usage))
            .d16_unorm
        else
            return error.NoDepthFormat;
        const color_format = device.swapchainTextureFormat(renderer.window);
        const environment = try lighting.Environment.init(device);
        errdefer environment.deinit(device);
        const pipeline = try createPipeline(.lit, device, color_format, depth_format);
        errdefer device.releaseGraphicsPipeline(pipeline);
        const shadow_pipeline = try createPipeline(.shadow, device, color_format, environment.shadow_format);
        errdefer device.releaseGraphicsPipeline(shadow_pipeline);
        const sky_pipeline = try createPipeline(.sky, device, color_format, depth_format);
        errdefer device.releaseGraphicsPipeline(sky_pipeline);
        if (!demo_imgui_init(renderer.window.handle, @ptrCast(device))) return error.ImGuiInit;
        log.log(.info, "scene", "导入场景已就绪，实体 {d}，深度格式 {s}，阴影图 {d}x{d} {s}", .{
            instance.entities.items.len, @tagName(depth_format),              lighting.shadow_size,
            lighting.shadow_size,        @tagName(environment.shadow_format),
        });
        return .{
            .registry = registry,
            .queue = RenderQueue.init(allocator),
            .assets = manager,
            .model = model,
            .instance = instance,
            .spinning_cube = spinning,
            .spin_base = spin_base,
            .device = device,
            .pipeline = pipeline,
            .shadow_pipeline = shadow_pipeline,
            .sky_pipeline = sky_pipeline,
            .environment = environment,
            .encode_srgb = switch (color_format) {
                .r8g8b8a8_unorm_srgb, .b8g8r8a8_unorm_srgb => 0,
                else => 1,
            },
            .depth_format = depth_format,
        };
    }

    pub fn deinit(self: *DemoScene) void {
        self.device.waitForIdle() catch {
            log.log(.warn, "scene", "等待 GPU 空闲失败: {s}", .{sdl.lastErrorText()});
        };
        demo_imgui_shutdown();
        if (self.depth) |depth| self.device.releaseTexture(depth);
        self.device.releaseGraphicsPipeline(self.sky_pipeline);
        self.device.releaseGraphicsPipeline(self.shadow_pipeline);
        self.device.releaseGraphicsPipeline(self.pipeline);
        self.environment.deinit(self.device);
        self.queue.deinit();
        self.instance.deinit(&self.registry);
        self.registry.deinit();
        self.assets.releaseModel(self.model) catch unreachable;
        self.assets.deinit();
    }

    pub fn processEvent(event: *const raw.SDL_Event) void {
        demo_imgui_event(event);
    }

    pub fn render(self: *DemoScene, renderer: GpuRenderer, input: *const InputState, dt: f32) !?GpuRenderer.Extent {
        const step = @min(dt, 0.05);
        const captured = input.mouseCaptured();
        if (captured) self.camera.update(input, step);
        if (self.spinning_cube) |entity| {
            self.rotation = @mod(self.rotation + step * self.rotation_speed, 200.0 * std.math.pi);
            const yaw = transform.Rotation.axisAngle(.{ 0, 1, 0 }, self.rotation);
            const tilt = transform.Rotation.axisAngle(.{ 1, 0, 0 }, self.rotation * 0.73);
            const rotation = (transform.Transform{ .rotation = tilt.mul(yaw) }).matrix();
            try self.registry.add(entity, transform.Transform{ .local_matrix = self.spin_base.mul(rotation) });
        }
        // Finish CPU work, including allocation, before acquiring a swapchain texture.
        const items = try self.queue.collect(&self.registry);

        const frame = (try renderer.acquireFrame()) orelse return null;
        self.record(frame, items, dt * 1000, captured) catch |err| {
            log.log(.error_, "scene", "录制场景命令失败: {s}", .{sdl.lastErrorText()});
            frame.submit() catch {};
            return err;
        };
        try frame.submit();
        return frame.extent;
    }

    fn record(self: *DemoScene, frame: GpuRenderer.Frame, items: []const RenderItem, frame_ms: f32, captured: bool) !void {
        const depth = try self.depthTarget(frame.extent);
        demo_imgui_prepare(@ptrCast(frame.commands), frame_ms, captured, if (self.spinning_cube != null) &self.rotation_speed else null, items.len);
        const projection = lighting.shadowProjection(&self.assets, items);
        const shadow = try frame.commands.beginRenderPass(&.{}, &.{
            .texture = self.environment.shadow,
            .load_op = .clear,
            .clear_depth = 1,
            .store_op = .store,
            .stencil_load_op = .dont_care,
            .stencil_store_op = .dont_care,
            .cycle = true,
        });
        shadow.bindGraphicsPipeline(self.shadow_pipeline);
        self.drawMeshes(.shadow, frame.commands, shadow, items, projection);
        shadow.end();

        const pass = try frame.commands.beginRenderPass(&.{frame.colorTarget(.clear)}, &.{
            .texture = depth,
            .load_op = .clear,
            .clear_depth = 1,
            .store_op = .dont_care,
            .stencil_load_op = .dont_care,
            .stencil_store_op = .dont_care,
            .cycle = true,
        });
        const aspect = @as(f32, @floatFromInt(frame.extent.width)) / @as(f32, @floatFromInt(frame.extent.height));
        pass.bindGraphicsPipeline(self.pipeline);
        const camera = self.camera.uniforms(aspect);
        frame.commands.pushFragmentUniform(1, lighting.Uniforms{ .eye = camera.eye, .projection = projection });
        pass.bindFragmentSamplers(2, &.{.{
            .texture = self.environment.shadow,
            .sampler = self.environment.shadow_sampler,
        }});
        self.drawMeshes(.lit, frame.commands, pass, items, camera);

        pass.bindGraphicsPipeline(self.sky_pipeline);
        pass.bindFragmentSamplers(0, &.{.{ .texture = self.environment.sky, .sampler = self.environment.sky_sampler }});
        frame.commands.pushVertexUniform(0, SkyUniforms{ .camera = camera, .flags = .{ self.encode_srgb, 0, 0, 0 } });
        pass.drawPrimitives(3, 1, 0, 0);
        pass.end();

        const overlay = try frame.commands.beginRenderPass(&.{frame.colorTarget(.load)}, null);
        demo_imgui_draw(@ptrCast(frame.commands), @ptrCast(overlay));
        overlay.end();
    }

    fn drawMeshes(
        self: *DemoScene,
        comptime kind: Pass,
        commands: *gpu.CommandBuffer,
        pass: *gpu.RenderPass,
        items: []const RenderItem,
        view: if (kind == .shadow) transform.Matrix else Camera.Uniforms,
    ) void {
        var bound_material: ?assets.MaterialHandle = null;
        var bound_mesh: ?assets.MeshHandle = null;
        for (items) |item| {
            const mesh = self.assets.mesh(item.mesh) orelse continue;
            if (bound_material == null or !std.meta.eql(bound_material.?, item.material)) {
                const material = self.assets.material(item.material) orelse continue;
                const texture = if (material.base_color_texture) |handle| self.assets.texture(handle) orelse continue else self.assets.white;
                const base: gpu.TextureSamplerBinding = .{ .texture = texture.image, .sampler = texture.sampler };
                const normal = if (material.normal_texture) |handle| self.assets.texture(handle) else null;
                if (kind == .shadow) {
                    pass.bindFragmentSamplers(0, &.{base});
                } else {
                    const normal_binding = normal orelse self.assets.white;
                    pass.bindFragmentSamplers(0, &.{
                        base,
                        .{ .texture = normal_binding.image, .sampler = normal_binding.sampler },
                    });
                }
                commands.pushFragmentUniform(0, MaterialUniforms{
                    .base_color = material.base_color,
                    .flags = .{
                        material.alpha_cutoff orelse -1,
                        self.encode_srgb,
                        @floatFromInt(@intFromBool(normal != null)),
                        @floatFromInt(@intFromBool(material.unlit)),
                    },
                    .surface = .{ material.normal_scale, material.roughness, 0, 0 },
                });
                bound_material = item.material;
            }
            if (bound_mesh == null or !std.meta.eql(bound_mesh.?, item.mesh)) {
                pass.bindVertexBuffers(0, &.{.{ .buffer = mesh.vertices }});
                pass.bindIndexBuffer(.{ .buffer = mesh.indices }, .u32);
                bound_mesh = item.mesh;
            }
            if (kind == .shadow) {
                commands.pushVertexUniform(0, ShadowUniforms{ .model = item.model, .projection = view });
            } else {
                commands.pushVertexUniform(0, DrawUniforms{ .camera = view, .model = item.model });
            }
            pass.drawIndexedPrimitives(mesh.index_count, 1, 0, 0, 0);
        }
    }

    fn depthTarget(self: *DemoScene, extent: GpuRenderer.Extent) !*gpu.Texture {
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

fn loadSceneAsset(manager: *assets.AssetManager, io: std.Io, path: ?[]const u8) !assets.ModelHandle {
    if (path) |file| return manager.loadFile(io, file);
    const bytes align(4) = @embedFile("demo.glb").*;
    return manager.loadEmbedded(io, "demo.glb", &bytes);
}

fn createPipeline(comptime kind: Pass, device: *gpu.Device, color: gpu.TextureFormat, depth: gpu.TextureFormat) !*gpu.GraphicsPipeline {
    const name = switch (kind) {
        .lit => "demo",
        .shadow => "shadow",
        .sky => "sky",
    };
    // SDL's Vulkan backend expects SPIR-V bytes aligned for uint32_t.
    const vertex_code align(4) = @embedFile(name ++ ".vert.spv").*;
    const fragment_code align(4) = @embedFile(name ++ ".frag.spv").*;
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
        .num_samplers = if (kind == .lit) 3 else 1,
        .num_uniform_buffers = switch (kind) {
            .lit => 2,
            .shadow => 1,
            .sky => 0,
        },
    });
    defer device.releaseShader(fragment);
    const targets = [_]gpu.ColorTargetDescription{.{ .format = color }};
    const attributes = [_]gpu.VertexAttribute{
        .{ .location = 0, .format = .float3, .offset = @offsetOf(Vertex, "position") },
        .{ .location = 1, .format = .float2, .offset = @offsetOf(Vertex, "uv") },
        .{ .location = 2, .format = .float3, .offset = @offsetOf(Vertex, "normal") },
        .{ .location = 3, .format = .float4, .offset = @offsetOf(Vertex, "tangent") },
    };
    return device.createGraphicsPipeline(.{
        .vertex_shader = vertex,
        .fragment_shader = fragment,
        .vertex_input_state = if (kind == .sky) .{} else .from(
            &.{.{ .pitch = @sizeOf(Vertex) }},
            if (kind == .lit) &attributes else attributes[0..2],
        ),
        .rasterizer_state = .{ .enable_depth_clip = true },
        .depth_stencil_state = .{
            .compare_op = if (kind == .sky) .less_or_equal else .less,
            .enable_depth_test = true,
            .enable_depth_write = kind != .sky,
        },
        .target_info = .{
            .color_target_descriptions = if (kind == .shadow) null else &targets,
            .num_color_targets = if (kind == .shadow) 0 else targets.len,
            .has_depth_stencil_target = true,
            .depth_stencil_format = depth,
        },
    });
}
