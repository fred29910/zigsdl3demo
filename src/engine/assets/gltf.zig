const std = @import("std");
const c = @import("gltf_c");
const Matrix = @import("../scene/transform.zig").Matrix;
const log = @import("zigsdl3demo").Logger.init(.info);

pub const Source = union(enum) { embedded: []const u8, file: []const u8 };
pub const Vertex = extern struct {
    position: [3]f32,
    uv: [2]f32 = @splat(0),
    normal: [3]f32 = @splat(0),
    tangent: [4]f32 = @splat(0),
};
pub const Primitive = struct {
    vertices: []const Vertex,
    indices: []const u32,
    material: u32,
};
pub const Range = struct { first: u32 = 0, count: u32 = 0 };
pub const Node = struct {
    name: []const u8,
    parent: ?usize,
    local: Matrix,
    primitives: Range,
};
pub const Image = struct { rgba: []const u8, width: u32, height: u32 };
pub const Sampler = struct {
    pub const Wrap = enum { repeat, mirror, clamp };
    min_linear: bool = true,
    mag_linear: bool = true,
    wrap_u: Wrap = .repeat,
    wrap_v: Wrap = .repeat,
};
pub const Texture = struct { image: Image, sampler: Sampler };
pub const Material = struct {
    base_color: [4]f32 = @splat(1),
    metallic: f32 = 1,
    roughness: f32 = 1,
    normal_scale: f32 = 1,
    unlit: bool = false,
    alpha_cutoff: ?f32 = null,
    base_color_texture: ?u32 = null,
    metallic_roughness_texture: ?u32 = null,
    normal_texture: ?u32 = null,
};

pub const Model = struct {
    arena: std.heap.ArenaAllocator,
    primitives: []const Primitive,
    nodes: []const Node,
    materials: []const Material,
    textures: []const ?Texture,

    pub fn deinit(self: *Model) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

const byte_limit: usize = 256 * 1024 * 1024;

pub fn load(allocator: std.mem.Allocator, io: std.Io, source: Source) !Model {
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();
    const temp = scratch.allocator();
    const path = switch (source) {
        .file => |path| path,
        .embedded => null,
    };
    const bytes = switch (source) {
        .embedded => |data| data,
        .file => |file| try std.Io.Dir.cwd().readFileAllocOptions(io, file, temp, .limited(byte_limit), .of(u32), null),
    };
    var data: [*c]c.cgltf_data = null;
    try check("parse", c.cgltf_parse(&std.mem.zeroes(c.cgltf_options), bytes.ptr, bytes.len, &data));
    defer c.cgltf_free(data);
    for (items(data.*.extensions_required, data.*.extensions_required_count)) |ptr| {
        const extension = std.mem.span(ptr);
        if (!std.mem.eql(u8, extension, "KHR_materials_unlit") and
            !std.mem.eql(u8, extension, "KHR_mesh_quantization"))
        {
            log.log(.error_, "assets", "不支持的 glTF 必需扩展 {s}", .{extension});
            return error.UnsupportedGltfExtension;
        }
    }
    for (items(data.*.buffers, data.*.buffers_count), 0..) |*buffer, index| {
        const content = if (buffer.uri != null)
            try readUri(temp, io, path, std.mem.span(buffer.uri))
        else if (index == 0 and data.*.bin != null)
            @as([*]const u8, @ptrCast(data.*.bin))[0..data.*.bin_size]
        else
            return error.MissingBuffer;
        if (content.len < buffer.size) return error.TruncatedGltfBuffer;
        // cgltf accesses buffer components through typed C pointers.
        buffer.data = @constCast(if (@intFromPtr(content.ptr) % @alignOf(u32) == 0) content.ptr else blk: {
            const aligned_bytes = try temp.alignedAlloc(u8, .of(u32), buffer.size);
            @memcpy(aligned_bytes, content[0..buffer.size]);
            break :blk aligned_bytes.ptr;
        });
    }
    try validateRanges(data);
    try check("validate", c.cgltf_validate(data));

    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const a = arena.allocator();
    const materials = try a.alloc(Material, data.*.materials_count + 1);
    @memset(materials, .{});
    const textures = try a.alloc(?Texture, data.*.textures_count);
    @memset(textures, null);
    const images = try temp.alloc(?Image, data.*.images_count);
    @memset(images, null);
    var reader: Reader = .{
        .data = data,
        .allocator = a,
        .temp = temp,
        .io = io,
        .path = path,
        .materials = materials,
        .textures = textures,
        .images = images,
        .used_materials = try temp.alloc(bool, materials.len),
    };
    @memset(reader.used_materials, false);

    const ranges = try temp.alloc(?Range, data.*.meshes_count);
    @memset(ranges, null);
    var primitives: std.ArrayList(Primitive) = .empty;
    var nodes: std.ArrayList(Node) = .empty;
    const Visit = struct { node: *const c.cgltf_node, parent: ?usize = null };
    var visits: std.ArrayList(Visit) = .empty;
    const selected = if (data.*.scene != null) data.*.scene else data.*.scenes;
    if (selected != null) {
        for (items(selected.*.nodes, selected.*.nodes_count)) |node| try visits.append(temp, .{ .node = node });
    } else {
        for (items(data.*.nodes, data.*.nodes_count)) |*node| {
            if (node.parent == null) try visits.append(temp, .{ .node = node });
        }
    }
    const visited = try temp.alloc(bool, data.*.nodes_count);
    @memset(visited, false);
    var cursor: usize = 0;
    while (cursor < visits.items.len) : (cursor += 1) {
        const visit = visits.items[cursor];
        const node = visit.node;
        const index = c.cgltf_node_index(data, node);
        if (visited[index]) return error.InvalidGltfHierarchy;
        visited[index] = true;
        if (node.skin != null or node.has_mesh_gpu_instancing != 0) return error.UnsupportedGltfNode;
        var range: Range = .{};
        if (node.mesh != null) {
            const mesh = node.mesh;
            const cached = &ranges[c.cgltf_mesh_index(data, mesh)];
            if (cached.* == null) {
                const first = std.math.cast(u32, primitives.items.len) orelse return error.AssetTooLarge;
                for (items(mesh.*.primitives, mesh.*.primitives_count)) |*primitive| {
                    try primitives.append(a, try reader.readPrimitive(primitive));
                }
                const end = std.math.cast(u32, primitives.items.len) orelse return error.AssetTooLarge;
                cached.* = .{ .first = first, .count = end - first };
            }
            range = cached.*.?;
        }
        var matrix: [16]f32 = undefined;
        c.cgltf_node_transform_local(node, &matrix);
        for (matrix) |component| if (!std.math.isFinite(component)) return error.InvalidNodeMatrix;
        if (matrix[3] != 0 or matrix[7] != 0 or matrix[11] != 0 or matrix[15] != 1)
            return error.InvalidNodeMatrix;
        try nodes.append(a, .{
            .name = if (node.name) |name| try a.dupe(u8, std.mem.span(name)) else "",
            .parent = visit.parent,
            .local = fromGltfMatrix(matrix),
            .primitives = range,
        });
        for (items(node.children, node.children_count)) |child| {
            try visits.append(temp, .{ .node = child, .parent = cursor });
        }
    }
    if (primitives.items.len == 0) return error.EmptyGltfScene;
    return .{ .arena = arena, .primitives = primitives.items, .nodes = nodes.items, .materials = materials, .textures = textures };
}

fn items(pointer: anytype, count: usize) []std.meta.Child(@TypeOf(pointer)) {
    return if (count == 0) &.{} else pointer[0..count];
}

fn fromGltfMatrix(m: [16]f32) Matrix {
    // glTF is column-major and right-handed. Convert the affine transform by S*M*S.
    return .{ .rows = .{
        .{ m[0], m[4], -m[8], m[12] },
        .{ m[1], m[5], -m[9], m[13] },
        .{ -m[2], -m[6], m[10], -m[14] },
    } };
}

fn check(stage: []const u8, result: c.cgltf_result) !void {
    if (result == c.cgltf_result_success) return;
    log.log(.error_, "assets", "cgltf {s} 失败，结果码 {d}", .{ stage, result });
    return switch (result) {
        c.cgltf_result_out_of_memory => error.OutOfMemory,
        c.cgltf_result_data_too_short => error.TruncatedGltfBuffer,
        else => error.InvalidGltf,
    };
}

fn readUri(a: std.mem.Allocator, io: std.Io, path: ?[]const u8, uri: []const u8) ![]const u8 {
    if (std.mem.startsWith(u8, uri, "data:")) {
        const comma = std.mem.indexOfScalar(u8, uri, ',') orelse return error.InvalidDataUri;
        if (!std.mem.endsWith(u8, uri[0..comma], ";base64")) return error.UnsupportedDataUri;
        const encoded = uri[comma + 1 ..];
        const decoder = std.base64.standard.Decoder;
        const size = try decoder.calcSizeForSlice(encoded);
        if (size >= byte_limit) return error.AssetTooLarge;
        const decoded = try a.alignedAlloc(u8, .of(u32), size);
        try decoder.decode(decoded, encoded);
        return decoded;
    }
    const base = path orelse return error.EmbeddedAssetHasExternalUri;
    const relative = std.Uri.percentDecodeInPlace(try a.dupe(u8, uri));
    if (relative.len == 0 or std.fs.path.isAbsolute(relative) or std.mem.indexOfAny(u8, relative, ":\\\x00?#") != null)
        return error.UnsupportedGltfUri;
    const joined = try std.fs.path.join(a, &.{ std.fs.path.dirname(base) orelse ".", relative });
    return std.Io.Dir.cwd().readFileAllocOptions(io, joined, a, .limited(byte_limit), .of(u32), null);
}

fn validateRanges(data: *const c.cgltf_data) !void {
    for (items(data.buffer_views, data.buffer_views_count)) |view| {
        if (view.has_meshopt_compression != 0) return error.UnsupportedMeshCompression;
        if (view.buffer == null or view.offset > view.buffer.*.size or view.size > view.buffer.*.size - view.offset)
            return error.TruncatedGltfBuffer;
    }
    for (items(data.accessors, data.accessors_count)) |accessor| {
        const size = c.cgltf_calc_size(accessor.type, accessor.component_type);
        const alignment = c.cgltf_component_size(accessor.component_type);
        if (size == 0 or alignment == 0 or accessor.count == 0) return error.InvalidAccessor;
        if (accessor.buffer_view != null)
            try validateSpan(accessor.buffer_view, accessor.offset, accessor.stride, accessor.count, size, alignment);
        if (accessor.is_sparse != 0) {
            const sparse = accessor.sparse;
            const index_size = c.cgltf_component_size(sparse.indices_component_type);
            // cgltf 1.15 reads sparse values using the accessor stride.
            if (accessor.stride != size) return error.UnsupportedSparseAccessor;
            if (index_size == 0 or sparse.count == 0 or sparse.count > accessor.count)
                return error.InvalidAccessor;
            try validateSpan(sparse.indices_buffer_view, sparse.indices_byte_offset, index_size, sparse.count, index_size, index_size);
            try validateSpan(sparse.values_buffer_view, sparse.values_byte_offset, size, sparse.count, size, alignment);
        }
    }
}

fn validateSpan(view: [*c]const c.cgltf_buffer_view, offset: usize, stride: usize, count: usize, size: usize, alignment: usize) !void {
    if (view == null or stride < size or offset > view.*.size or size > view.*.size - offset or
        count - 1 > (view.*.size - offset - size) / stride) return error.TruncatedGltfBuffer;
    if ((view.*.offset + offset) % alignment != 0 or stride % alignment != 0)
        return error.MisalignedAccessor;
}

const Reader = struct {
    data: *const c.cgltf_data,
    allocator: std.mem.Allocator,
    temp: std.mem.Allocator,
    io: std.Io,
    path: ?[]const u8,
    materials: []Material,
    textures: []?Texture,
    images: []?Image,
    used_materials: []bool,

    fn readPrimitive(self: *Reader, primitive: *const c.cgltf_primitive) !Primitive {
        if (primitive.type != c.cgltf_primitive_type_triangles) return error.UnsupportedPrimitiveMode;
        if (primitive.targets_count != 0 or primitive.has_draco_mesh_compression != 0)
            return error.UnsupportedGltfPrimitive;
        const position = c.cgltf_find_accessor(primitive, c.cgltf_attribute_type_position, 0);
        if (position == null) return error.MissingPositions;
        const count = position.*.count;
        if (count > byte_limit / @sizeOf(Vertex)) return error.AssetTooLarge;
        const vertices = try self.allocator.alloc(Vertex, count);
        const values = try self.temp.alloc(f32, count * 4);
        defer self.temp.free(values);
        for (vertices) |*vertex| vertex.* = .{ .position = undefined };
        try readAttribute("position", 3, position, vertices, values, .{ 1, 1, -1 });
        try readAttribute("uv", 2, c.cgltf_find_accessor(primitive, c.cgltf_attribute_type_texcoord, 0), vertices, values, .{ 1, 1 });
        try readAttribute("normal", 3, c.cgltf_find_accessor(primitive, c.cgltf_attribute_type_normal, 0), vertices, values, .{ 1, 1, -1 });
        try readAttribute("tangent", 4, c.cgltf_find_accessor(primitive, c.cgltf_attribute_type_tangent, 0), vertices, values, .{ 1, 1, -1, -1 });

        const index_count = if (primitive.indices != null) primitive.indices.*.count else count;
        if (index_count == 0 or index_count % 3 != 0) return error.InvalidTriangleCount;
        if (index_count > byte_limit / @sizeOf(u32)) return error.AssetTooLarge;
        const indices = try self.allocator.alloc(u32, index_count);
        if (primitive.indices != null) {
            if (primitive.indices.*.is_sparse != 0) return error.UnsupportedSparseAccessor;
            if (c.cgltf_accessor_unpack_indices(primitive.indices, indices.ptr, @sizeOf(u32), indices.len) != indices.len)
                return error.InvalidIndices;
        } else {
            for (indices, 0..) |*index, i| index.* = @intCast(i);
        }
        for (indices) |index| if (index >= count) return error.InvalidIndices;
        var i: usize = 0;
        while (i < indices.len) : (i += 3) std.mem.swap(u32, &indices[i + 1], &indices[i + 2]);
        const material = try self.readMaterial(primitive.material);
        const m = self.materials[material];
        if ((m.base_color_texture != null or m.normal_texture != null or m.metallic_roughness_texture != null) and
            c.cgltf_find_accessor(primitive, c.cgltf_attribute_type_texcoord, 0) == null)
            return error.MissingTexcoords;
        return .{ .vertices = vertices, .indices = indices, .material = material };
    }

    fn readMaterial(self: *Reader, material: [*c]const c.cgltf_material) !u32 {
        if (material == null) return 0;
        const index = std.math.cast(u32, c.cgltf_material_index(self.data, material) + 1) orelse return error.AssetTooLarge;
        if (self.used_materials[index]) return index;
        const alpha: ?f32 = switch (material.*.alpha_mode) {
            c.cgltf_alpha_mode_opaque => null,
            c.cgltf_alpha_mode_mask => material.*.alpha_cutoff,
            else => return error.UnsupportedAlphaMode,
        };
        const pbr = material.*.pbr_metallic_roughness;
        self.materials[index] = .{
            .base_color = pbr.base_color_factor,
            .metallic = pbr.metallic_factor,
            .roughness = pbr.roughness_factor,
            .normal_scale = material.*.normal_texture.scale,
            .unlit = material.*.unlit != 0,
            .alpha_cutoff = alpha,
            .base_color_texture = try self.readTexture(pbr.base_color_texture),
            .metallic_roughness_texture = try self.readTexture(pbr.metallic_roughness_texture),
            .normal_texture = try self.readTexture(material.*.normal_texture),
        };
        self.used_materials[index] = true;
        return index;
    }

    fn readTexture(self: *Reader, view: c.cgltf_texture_view) !?u32 {
        if (view.texture == null) return null;
        if (view.texcoord != 0 or view.has_transform != 0) return error.UnsupportedTextureCoordinates;
        const texture = view.texture.*;
        if (texture.image == null) return error.UnsupportedImage;
        const index = std.math.cast(u32, c.cgltf_texture_index(self.data, view.texture)) orelse return error.AssetTooLarge;
        if (self.textures[index] == null) {
            const image_index = c.cgltf_image_index(self.data, texture.image);
            if (self.images[image_index] == null) self.images[image_index] = try self.readImage(texture.image.*);
            self.textures[index] = .{ .image = self.images[image_index].?, .sampler = samplerInfo(texture.sampler) };
        }
        return index;
    }

    fn readImage(self: *Reader, image: c.cgltf_image) !Image {
        const encoded = if (image.buffer_view != null)
            c.cgltf_buffer_view_data(image.buffer_view)[0..image.buffer_view.*.size]
        else if (image.uri != null)
            try readUri(self.temp, self.io, self.path, std.mem.span(image.uri))
        else
            return error.MissingImage;
        const len = std.math.cast(c_int, encoded.len) orelse return error.AssetTooLarge;
        var width: c_int = 0;
        var height: c_int = 0;
        const pixels = c.stbi_load_from_memory(encoded.ptr, len, &width, &height, null, 4);
        if (pixels == null) {
            log.log(.error_, "assets", "PNG/JPEG 解码失败: {s}", .{std.mem.span(c.stbi_failure_reason())});
            return error.InvalidImage;
        }
        defer c.stbi_image_free(pixels);
        const w: u32 = @intCast(width);
        const h: u32 = @intCast(height);
        return .{ .rgba = try self.allocator.dupe(u8, pixels[0 .. @as(usize, w) * h * 4]), .width = w, .height = h };
    }
};

fn readAttribute(comptime field: []const u8, comptime n: usize, accessor: [*c]const c.cgltf_accessor, vertices: []Vertex, values: []f32, signs: [n]f32) !void {
    if (accessor == null) return;
    const vector_type = switch (n) {
        2 => c.cgltf_type_vec2,
        3 => c.cgltf_type_vec3,
        4 => c.cgltf_type_vec4,
        else => unreachable,
    };
    if (accessor.*.type != vector_type or accessor.*.count != vertices.len)
        return error.InvalidVertexAttribute;
    const data = values[0 .. vertices.len * n];
    if (c.cgltf_accessor_unpack_floats(accessor, data.ptr, data.len) != data.len)
        return error.InvalidVertexAttribute;
    for (vertices, 0..) |*vertex, i| {
        for (0..n) |axis| {
            const value = data[i * n + axis];
            if (!std.math.isFinite(value)) return error.InvalidVertexAttribute;
            @field(vertex, field)[axis] = value * signs[axis];
        }
    }
}

fn samplerInfo(sampler: [*c]const c.cgltf_sampler) Sampler {
    if (sampler == null) return .{};
    return .{
        .min_linear = switch (sampler.*.min_filter) {
            c.cgltf_filter_type_nearest, c.cgltf_filter_type_nearest_mipmap_nearest, c.cgltf_filter_type_nearest_mipmap_linear => false,
            else => true,
        },
        .mag_linear = sampler.*.mag_filter != c.cgltf_filter_type_nearest,
        .wrap_u = wrap(sampler.*.wrap_s),
        .wrap_v = wrap(sampler.*.wrap_t),
    };
}

fn wrap(mode: c.cgltf_wrap_mode) Sampler.Wrap {
    return switch (mode) {
        c.cgltf_wrap_mode_clamp_to_edge => .clamp,
        c.cgltf_wrap_mode_mirrored_repeat => .mirror,
        else => .repeat,
    };
}

test "GLB import preserves shared meshes, hierarchy, material, and handedness" {
    const bytes align(4) = @embedFile("demo.glb").*;
    var model = try load(std.testing.allocator, std.testing.io, .{ .embedded = &bytes });
    defer model.deinit();

    try std.testing.expectEqual(@as(usize, 4), model.nodes.len);
    try std.testing.expectEqual(@as(usize, 4), model.primitives.len);
    try std.testing.expectEqual(@as(?usize, 0), model.nodes[3].parent);
    try std.testing.expectEqual(model.nodes[0].primitives, model.nodes[3].primitives);
    try std.testing.expectEqual(@as(u32, 2), model.nodes[0].primitives.count);
    try std.testing.expectEqual(@as(f32, 1.2), model.nodes[1].local.rows[2][3]);
    try std.testing.expectEqualSlices(u32, &.{ 0, 2, 1 }, model.primitives[2].indices);
    const first = model.primitives[0].vertices[0];
    try std.testing.expectEqual([3]f32{ -1, -1, -1 }, first.position);
    try std.testing.expectEqual([3]f32{ 0, 0, -1 }, first.normal);
    try std.testing.expectEqual([4]f32{ 1, 0, 0, 1 }, first.tangent);
    try std.testing.expectEqual([2]f32{ 0, 1 }, first.uv);
    const material = model.materials[model.primitives[0].material];
    try std.testing.expectEqual(@as(f32, 0.75), material.roughness);
    try std.testing.expectEqual(@as(f32, 0), material.metallic);
    try std.testing.expectEqual(@as(f32, 0.8), material.normal_scale);
    try std.testing.expect(material.normal_texture.? != material.base_color_texture.?);
    const texture = model.textures[material.base_color_texture.?].?;
    try std.testing.expectEqual(@as(u32, 32), texture.image.width);
    try std.testing.expectEqualSlices(u8, &.{ 241, 146, 59, 255 }, texture.image.rgba[0..4]);
}

test "glTF rejects out-of-range buffer view before reading accessors" {
    const json =
        \\{"asset":{"version":"2.0"},
        \\"buffers":[{"byteLength":4,"uri":"data:application/octet-stream;base64,AAAAAA=="}],
        \\"bufferViews":[{"buffer":0,"byteOffset":4,"byteLength":4}]}
    ;
    try std.testing.expectError(
        error.TruncatedGltfBuffer,
        load(std.testing.allocator, std.testing.io, .{ .embedded = json }),
    );
}

test "base64 buffer provides aligned float vertices and u16 indices" {
    const json =
        \\{"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],
        \\"nodes":[{"mesh":0}],"meshes":[{"primitives":[{"attributes":{"POSITION":0},"indices":1}]}],
        \\"buffers":[{"byteLength":42,"uri":"data:application/octet-stream;base64,AAAAAAAAAAAAAAAAAACAPwAAAAAAAAAAAAAAAAAAgD8AAAAAAAABAAIA"}],
        \\"bufferViews":[{"buffer":0,"byteLength":36},{"buffer":0,"byteOffset":36,"byteLength":6}],
        \\"accessors":[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3","min":[0,0,0],"max":[1,1,0]},
        \\{"bufferView":1,"componentType":5123,"count":3,"type":"SCALAR"}]}
    ;
    var model = try load(std.testing.allocator, std.testing.io, .{ .embedded = json });
    defer model.deinit();
    try std.testing.expectEqual([3]f32{ 0, 1, 0 }, model.primitives[0].vertices[2].position);
    try std.testing.expectEqualSlices(u32, &.{ 0, 2, 1 }, model.primitives[0].indices);
    try std.testing.expectEqual(@as(u32, 0), model.primitives[0].material);
}
