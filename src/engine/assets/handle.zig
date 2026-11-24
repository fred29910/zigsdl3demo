const Kind = enum { model, mesh, material, texture };

fn Handle(comptime kind: Kind) type {
    return struct {
        index: u64,
        generation: u32,

        pub const asset_kind = kind;
    };
}

pub const ModelHandle = Handle(.model);
pub const MeshHandle = Handle(.mesh);
pub const MaterialHandle = Handle(.material);
pub const TextureHandle = Handle(.texture);

// A subresource index packs the owning model slot and the local array index.
pub fn subresource(comptime T: type, model: ModelHandle, local: u32) T {
    return .{ .index = (model.index << 32) | local, .generation = model.generation };
}

pub fn owner(handle: anytype) ModelHandle {
    return .{ .index = handle.index >> 32, .generation = handle.generation };
}

pub fn localIndex(handle: anytype) u32 {
    return @truncate(handle.index);
}
