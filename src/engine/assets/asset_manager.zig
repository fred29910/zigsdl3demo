const std = @import("std");
const sdl = @import("sdl3");
const gpu = sdl.gpu;
const gltf = @import("gltf.zig");
const handles = @import("handle.zig");
const log = @import("zigsdl3demo").Logger.init(.info);

pub const ModelHandle = handles.ModelHandle;
pub const MeshHandle = handles.MeshHandle;
pub const MaterialHandle = handles.MaterialHandle;
pub const TextureHandle = handles.TextureHandle;

pub const Mesh = struct {
    vertices: *gpu.Buffer,
    indices: *gpu.Buffer,
    index_count: u32,
    material: MaterialHandle,
    bounds: Bounds,

    fn release(self: Mesh, device: *gpu.Device) void {
        device.releaseBuffer(self.indices);
        device.releaseBuffer(self.vertices);
    }
};

pub const Bounds = struct {
    min: @Vector(3, f32) = @splat(std.math.inf(f32)),
    max: @Vector(3, f32) = @splat(-std.math.inf(f32)),

    pub fn include(self: *Bounds, point: @Vector(3, f32)) void {
        self.min = @min(self.min, point);
        self.max = @max(self.max, point);
    }
};

pub const Texture = struct {
    image: *gpu.Texture,
    sampler: *gpu.Sampler,

    fn release(self: Texture, device: *gpu.Device) void {
        device.releaseSampler(self.sampler);
        device.releaseTexture(self.image);
    }
};

pub const Material = struct {
    base_color: [4]f32,
    metallic: f32,
    roughness: f32,
    normal_scale: f32,
    unlit: bool,
    alpha_cutoff: ?f32,
    base_color_texture: ?TextureHandle,
    metallic_roughness_texture: ?TextureHandle,
    normal_texture: ?TextureHandle,
};

pub const Model = struct {
    arena: std.heap.ArenaAllocator,
    key: []const u8,
    nodes: []const gltf.Node,
    meshes: []const Mesh,
    materials: []const Material,
    textures: []const ?Texture,

    fn release(self: *Model, device: *gpu.Device) void {
        for (self.textures) |texture| if (texture) |t| t.release(device);
        for (self.meshes) |mesh| mesh.release(device);
        self.arena.deinit();
    }
};

/// Synchronous cache owned by a single render thread and GPU device.
/// Each load retains a model. Its subresources live until the final release.
pub const AssetManager = struct {
    allocator: std.mem.Allocator,
    device: *gpu.Device,
    by_path: std.StringHashMapUnmanaged(ModelHandle) = .empty,
    slots: std.ArrayList(Slot) = .empty,
    free_head: ?u32 = null,
    white: Texture,

    const Slot = struct {
        generation: u32 = 1,
        references: u32 = 0,
        model: ?Model = null,
        next_free: ?u32 = null,
    };

    pub fn init(allocator: std.mem.Allocator, device: *gpu.Device) !AssetManager {
        const white = try uploadTexture(device, .{
            .image = .{ .width = 1, .height = 1, .rgba = &.{ 255, 255, 255, 255 } },
            .sampler = .{},
        }, .r8g8b8a8_unorm_srgb);
        return .{ .allocator = allocator, .device = device, .white = white };
    }

    pub fn deinit(self: *AssetManager) void {
        self.by_path.deinit(self.allocator);
        for (self.slots.items) |*slot| if (slot.model) |*entry| entry.release(self.device);
        self.slots.deinit(self.allocator);
        self.white.release(self.device);
        self.* = undefined;
    }

    pub fn loadFile(self: *AssetManager, io: std.Io, file: []const u8) !ModelHandle {
        const canonical = try std.Io.Dir.cwd().realPathFileAlloc(io, file, self.allocator);
        defer self.allocator.free(canonical);
        return self.load(io, canonical, .{ .file = canonical });
    }

    /// The name identifies immutable embedded content within this manager.
    pub fn loadEmbedded(self: *AssetManager, io: std.Io, name: []const u8, bytes: []const u8) !ModelHandle {
        const key = try std.fmt.allocPrint(self.allocator, "embedded:{s}", .{name});
        defer self.allocator.free(key);
        return self.load(io, key, .{ .embedded = bytes });
    }

    fn load(self: *AssetManager, io: std.Io, key: []const u8, source: gltf.Source) !ModelHandle {
        if (self.by_path.get(key)) |existing| {
            const slot = &self.slots.items[@intCast(existing.index)];
            if (slot.references == std.math.maxInt(u32)) return error.AssetReferenceLimit;
            slot.references += 1;
            log.log(.info, "assets", "缓存命中 {s}，引用数 {d}", .{ key, slot.references });
            return existing;
        }

        const index = self.free_head orelse std.math.cast(u32, self.slots.items.len) orelse return error.AssetLimit;
        const generation = if (self.free_head != null) self.slots.items[index].generation else 1;
        if (self.free_head == null) try self.slots.ensureUnusedCapacity(self.allocator, 1);
        try self.by_path.ensureUnusedCapacity(self.allocator, 1);
        const handle: ModelHandle = .{ .index = index, .generation = generation };
        var cpu = try gltf.load(self.allocator, io, source);
        defer cpu.deinit();
        const entry = try self.uploadModel(key, handle, cpu);
        const slot: Slot = .{ .model = entry, .references = 1, .generation = generation };
        if (self.free_head != null) {
            self.free_head = self.slots.items[index].next_free;
            self.slots.items[index] = slot;
        } else {
            self.slots.appendAssumeCapacity(slot);
        }
        self.by_path.putAssumeCapacityNoClobber(entry.key, handle);
        log.log(.info, "assets", "已加载 {s}，节点 {d}，网格图元 {d}", .{ key, entry.nodes.len, entry.meshes.len });
        return handle;
    }

    /// Drop the caller's reference after its scene entities have been removed.
    /// SDL releases submitted GPU resources when they are safe to destroy.
    pub fn releaseModel(self: *AssetManager, handle: ModelHandle) error{InvalidModelHandle}!void {
        if (self.model(handle) == null) return error.InvalidModelHandle;
        const slot = &self.slots.items[@intCast(handle.index)];
        slot.references -= 1;
        if (slot.references != 0) return;
        const model_data = &slot.model.?;
        _ = self.by_path.remove(model_data.key);
        model_data.release(self.device);
        slot.model = null;
        if (slot.generation < std.math.maxInt(u32)) {
            slot.generation += 1;
            slot.next_free = self.free_head;
            self.free_head = @intCast(handle.index);
        }
    }

    pub fn model(self: *const AssetManager, handle: ModelHandle) ?*const Model {
        if (handle.index >= self.slots.items.len) return null;
        const slot = &self.slots.items[@intCast(handle.index)];
        if (slot.generation != handle.generation or slot.references == 0) return null;
        return if (slot.model) |*entry| entry else null;
    }

    pub fn mesh(self: *const AssetManager, handle: MeshHandle) ?Mesh {
        const owner = self.model(handles.owner(handle)) orelse return null;
        const index = handles.localIndex(handle);
        return if (index < owner.meshes.len) owner.meshes[index] else null;
    }

    pub fn material(self: *const AssetManager, handle: MaterialHandle) ?Material {
        const owner = self.model(handles.owner(handle)) orelse return null;
        const index = handles.localIndex(handle);
        return if (index < owner.materials.len) owner.materials[index] else null;
    }

    pub fn texture(self: *const AssetManager, handle: TextureHandle) ?Texture {
        const owner = self.model(handles.owner(handle)) orelse return null;
        const index = handles.localIndex(handle);
        return if (index < owner.textures.len) owner.textures[index] else null;
    }

    fn uploadModel(self: *AssetManager, key: []const u8, handle: ModelHandle, cpu: gltf.Model) !Model {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        errdefer arena.deinit();
        const a = arena.allocator();
        const meshes = try a.alloc(Mesh, cpu.primitives.len);
        const materials = try a.alloc(Material, cpu.materials.len);
        if (cpu.textures.len > std.math.maxInt(u32) / 2) return error.AssetTooLarge;
        const textures = try a.alloc(?Texture, cpu.textures.len * 2);
        @memset(textures, null);
        const owned_key = try a.dupe(u8, key);
        const nodes = try a.dupe(gltf.Node, cpu.nodes);
        var uploaded: usize = 0;
        errdefer for (meshes[0..uploaded]) |mesh_data| mesh_data.release(self.device);
        errdefer for (textures) |texture_data| if (texture_data) |t| t.release(self.device);
        for (cpu.primitives, meshes) |primitive, *out| {
            out.* = try uploadMesh(self.device, primitive, handles.subresource(MaterialHandle, handle, primitive.material));
            uploaded += 1;
        }
        for (cpu.materials, materials) |source, *out| {
            out.* = .{
                .base_color = source.base_color,
                .metallic = source.metallic,
                .roughness = source.roughness,
                .alpha_cutoff = source.alpha_cutoff,
                .normal_scale = source.normal_scale,
                .unlit = source.unlit,
                .base_color_texture = try self.materialTexture(handle, cpu.textures, textures, source.base_color_texture, true),
                .metallic_roughness_texture = try self.materialTexture(handle, cpu.textures, textures, source.metallic_roughness_texture, false),
                .normal_texture = try self.materialTexture(handle, cpu.textures, textures, source.normal_texture, false),
            };
        }
        return .{ .arena = arena, .key = owned_key, .nodes = nodes, .meshes = meshes, .materials = materials, .textures = textures };
    }

    fn materialTexture(self: *AssetManager, model_handle: ModelHandle, sources: []const ?gltf.Texture, textures: []?Texture, index: ?u32, srgb: bool) !?TextureHandle {
        const source_index = index orelse return null;
        const slot = source_index * 2 + @intFromBool(srgb);
        if (textures[slot] == null) {
            const format: gpu.TextureFormat = if (srgb) .r8g8b8a8_unorm_srgb else .r8g8b8a8_unorm;
            textures[slot] = try uploadTexture(self.device, sources[source_index].?, format);
        }
        return handles.subresource(TextureHandle, model_handle, slot);
    }
};

fn uploadMesh(device: *gpu.Device, primitive: gltf.Primitive, material: MaterialHandle) !Mesh {
    const vertices = std.mem.sliceAsBytes(primitive.vertices);
    const indices = std.mem.sliceAsBytes(primitive.indices);
    const vertex_size: u32 = @intCast(vertices.len);
    const index_size: u32 = @intCast(indices.len);
    const vertex_buffer = try device.createBuffer(.{ .usage = .{ .vertex = true }, .size = vertex_size });
    errdefer device.releaseBuffer(vertex_buffer);
    const index_buffer = try device.createBuffer(.{ .usage = .{ .index = true }, .size = index_size });
    errdefer device.releaseBuffer(index_buffer);
    const staging_size = vertex_size + index_size;
    const transfer = try device.createTransferBuffer(.{ .size = staging_size });
    defer device.releaseTransferBuffer(transfer);
    const memory = try device.mapTransferBuffer(transfer, staging_size, false);
    @memcpy(memory[0..vertex_size], vertices);
    @memcpy(memory[vertex_size..], indices);
    device.unmapTransferBuffer(transfer);
    const commands = try device.acquireCommandBuffer();
    const pass = try beginCopy(commands);
    pass.uploadToBuffer(.{ .transfer_buffer = transfer }, .{ .buffer = vertex_buffer, .size = vertex_size }, false);
    pass.uploadToBuffer(.{ .transfer_buffer = transfer, .offset = vertex_size }, .{ .buffer = index_buffer, .size = index_size }, false);
    pass.end();
    try commands.submit();
    var bounds: Bounds = .{};
    for (primitive.vertices) |vertex| bounds.include(vertex.position);
    return .{
        .vertices = vertex_buffer,
        .indices = index_buffer,
        .index_count = @intCast(primitive.indices.len),
        .material = material,
        .bounds = bounds,
    };
}

fn uploadTexture(device: *gpu.Device, source: gltf.Texture, format: gpu.TextureFormat) !Texture {
    const image = source.image;
    const pixels = image.rgba;
    const size: u32 = @intCast(pixels.len);
    const texture = try device.createTexture(.{
        .format = format,
        .usage = .{ .sampler = true },
        .width = image.width,
        .height = image.height,
    });
    errdefer device.releaseTexture(texture);
    const sampler = try device.createSampler(.{
        .mag_filter = if (source.sampler.mag_linear) .linear else .nearest,
        .min_filter = if (source.sampler.min_linear) .linear else .nearest,
        .address_mode_u = addressMode(source.sampler.wrap_u),
        .address_mode_v = addressMode(source.sampler.wrap_v),
    });
    errdefer device.releaseSampler(sampler);
    const transfer = try device.createTransferBuffer(.{ .size = size });
    defer device.releaseTransferBuffer(transfer);
    const memory = try device.mapTransferBuffer(transfer, size, false);
    @memcpy(memory, pixels);
    device.unmapTransferBuffer(transfer);
    const commands = try device.acquireCommandBuffer();
    const pass = try beginCopy(commands);
    pass.uploadToTexture(.{ .transfer_buffer = transfer }, .{ .texture = texture, .w = image.width, .h = image.height }, false);
    pass.end();
    try commands.submit();
    return .{ .image = texture, .sampler = sampler };
}

fn beginCopy(commands: *gpu.CommandBuffer) !*gpu.CopyPass {
    return commands.beginCopyPass() catch |err| {
        commands.cancel() catch {};
        return err;
    };
}

fn addressMode(mode: gltf.Sampler.Wrap) gpu.SamplerAddressMode {
    return switch (mode) {
        .repeat => .repeat,
        .mirror => .mirrored_repeat,
        .clamp => .clamp_to_edge,
    };
}
