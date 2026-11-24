const std = @import("std");
const builtin = @import("builtin");

comptime {
    if (!std.mem.eql(u8, builtin.zig_version_string, "0.17.1"))
        @compileError("zigsdl3demo requires Zig 0.17.1");
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const demo_2d = b.option(bool, "demo-2d", "Run the M1 SDL 2D input demo") orelse false;
    const clear_only = b.option(bool, "clear-only", "Run the M2 Vulkan clear demo") orelse false;
    const options = b.addOptions();
    options.addOption(bool, "demo_2d", demo_2d);
    options.addOption(bool, "clear_only", clear_only);

    const core = b.addModule("zigsdl3demo", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const sdl_package = b.dependency("sdl3", .{
        .target = target,
        .optimize = optimize,
    });
    const sdl3 = sdl_package.module("sdl3");
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
    exe.root_module.addOptions("build_options", options);
    configureShaders(b, exe.root_module);
    if (!demo_2d and !clear_only) {
        configureAssets(b, exe.root_module);
        if (b.lazyDependency("imgui", .{})) |imgui| {
            const app = exe.root_module;
            app.link_libcpp = true;
            app.addIncludePath(imgui.path(""));
            app.addIncludePath(imgui.path("backends"));
            app.addIncludePath(sdl_package.artifact("SDL3").getEmittedIncludeTree());
            app.addCSourceFiles(.{
                .root = imgui.path(""),
                .files = &.{
                    "imgui.cpp",                    "imgui_draw.cpp",                  "imgui_widgets.cpp", "imgui_tables.cpp",
                    "backends/imgui_impl_sdl3.cpp", "backends/imgui_impl_sdlgpu3.cpp",
                },
                .flags = &.{"-std=c++17"},
            });
            app.addCSourceFile(.{ .file = b.path("src/engine/renderer/imgui_bridge.cpp"), .flags = &.{"-std=c++17"} });
        }
    }
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    run.addPassthruArgs();
    run.step.dependOn(b.getInstallStep());
    b.step("run", "Run the SDL3 GPU demo").dependOn(&run.step);

    const test_step = b.step("test", "Run core, SDL platform, and demo tests");
    test_step.dependOn(&exe.step);
    for ([_]*std.Build.Module{ core, platform, exe.root_module }) |module| {
        const tests = b.addTest(.{ .root_module = module });
        test_step.dependOn(&b.addRunArtifact(tests).step);
    }
}

fn configureAssets(b: *std.Build, app: *std.Build.Module) void {
    app.addAnonymousImport("demo.glb", .{ .root_source_file = b.path("assets/demo.glb") });
    const cgltf = b.lazyDependency("cgltf", .{});
    const stb = b.lazyDependency("stb", .{});
    if (cgltf == null or stb == null) return;
    const headers = b.addTranslateC(.{
        .root_source_file = b.path("src/engine/assets/gltf_libraries.h"),
        .target = app.resolved_target.?,
        .optimize = app.optimize.?,
        .link_libc = true,
    });
    headers.addIncludePath(cgltf.?.path(""));
    headers.addIncludePath(stb.?.path(""));
    app.addImport("gltf_c", headers.createModule());
    app.addIncludePath(cgltf.?.path(""));
    app.addIncludePath(stb.?.path(""));
    app.addCSourceFile(.{ .file = b.path("src/engine/assets/gltf_libraries.c"), .flags = &.{} });
}

fn configureShaders(b: *std.Build, app: *std.Build.Module) void {
    const tool: ?[]const u8 = if (b.option([]const u8, "shadercross", "Path to SDL_shadercross for rebuilding embedded shaders")) |path|
        path
    else
        b.findProgram(.{ .names = &.{"shadercross"} });
    const shaders = b.step("shaders", "Compile HLSL to SPIR-V and install the results");
    const programs = .{
        .{ "demo.vert", "vertex" },
        .{ "demo.frag", "fragment" },
        .{ "shadow.vert", "vertex" },
        .{ "shadow.frag", "fragment" },
        .{ "sky.vert", "vertex" },
        .{ "sky.frag", "fragment" },
    };
    inline for (programs) |program| {
        const name, const stage = program;
        const compile = b.addSystemCommand(&.{tool orelse "shadercross"});
        compile.addFileArg(b.path("shaders/" ++ name ++ ".hlsl"));
        compile.addArgs(&.{ "-s", "HLSL", "-d", "SPIRV", "-t", stage, "-o" });
        const generated = compile.addOutputFileArg(name ++ ".spv");
        shaders.dependOn(&b.addInstallFile(generated, "shaders/" ++ name ++ ".spv").step);
        app.addAnonymousImport(name ++ ".spv", .{
            .root_source_file = if (tool != null) generated else b.path("shaders/" ++ name ++ ".spv"),
        });
    }
}
