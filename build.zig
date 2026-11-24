const std = @import("std");
const builtin = @import("builtin");

comptime {
    if (!std.mem.eql(u8, builtin.zig_version_string, "0.17.1"))
        @compileError("zigsdl3demo requires Zig 0.17.1");
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const core = b.addModule("zigsdl3demo", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const sdl3 = b.dependency("sdl3", .{
        .target = target,
        .optimize = optimize,
    }).module("sdl3");
    const platform = b.addModule("engine.platform.sdl", .{
        .root_source_file = b.path("src/engine/platform/sdl.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "sdl3", .module = sdl3 }},
    });

    const exe = b.addExecutable(.{
        .name = "zigsdl3demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigsdl3demo", .module = core },
                .{ .name = "sdl3", .module = sdl3 },
                .{ .name = "engine.platform.sdl", .module = platform },
            },
        }),
    });
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    b.step("run", "Run the SDL3 demo").dependOn(&run.step);

    const test_step = b.step("test", "Run core, SDL platform, and demo tests");
    for ([_]*std.Build.Module{ core, platform, exe.root_module }) |module| {
        const tests = b.addTest(.{ .root_module = module });
        test_step.dependOn(&b.addRunArtifact(tests).step);
    }
}
