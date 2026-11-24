// Built-in demo resources. Asset-backed handles are introduced in M5.
pub const MeshId = enum { cube, triangle };
pub const MaterialId = enum { checker };

pub const MeshRenderer = struct {
    mesh: MeshId,
    material: MaterialId = .checker,
};
