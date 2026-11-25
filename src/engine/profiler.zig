//! Tracy C ABI for opt-in CPU zones. The regular build compiles each call away.
const enabled = @import("build_options").tracy;

const SourceLocation = extern struct {
    name: [*:0]const u8,
    function: [*:0]const u8,
    file: [*:0]const u8,
    line: u32,
    color: u32 = 0,
};
const Context = extern struct { id: u32, active: i32 };

extern fn ___tracy_emit_zone_begin(*const SourceLocation, i32) Context;
extern fn ___tracy_emit_zone_end(Context) void;
extern fn ___tracy_emit_frame_mark(?[*:0]const u8) void;

pub const Zone = if (enabled) Context else void;

pub inline fn begin(comptime name: [:0]const u8, comptime source: @import("std").builtin.SourceLocation) Zone {
    if (enabled) {
        const Location = struct {
            const data: SourceLocation = .{ .name = name.ptr, .function = source.fn_name.ptr, .file = source.file.ptr, .line = source.line };
        };
        return ___tracy_emit_zone_begin(&Location.data, 1);
    }
}

pub inline fn end(zone: Zone) void {
    if (enabled) ___tracy_emit_zone_end(zone);
}

pub inline fn frame() void {
    if (enabled) ___tracy_emit_frame_mark(null);
}
