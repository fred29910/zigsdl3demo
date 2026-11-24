const handles = @import("../assets/handle.zig");

pub const MeshRenderer = struct {
    mesh: handles.MeshHandle,
    material: handles.MaterialHandle,
};
