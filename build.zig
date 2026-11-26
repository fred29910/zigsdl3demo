const std = @import("std");
const builtin = @import("builtin");

comptime {
    if (!std.mem.eql(u8, builtin.zig_version_string, "0.17.1"))
        @compileError("zigsdl3demo requires Zig 0.17.1");
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = optimizeOption(b);
    const demo_2d = b.option(bool, "demo-2d", "Run the M1 SDL 2D input demo") orelse false;
    const clear_only = b.option(bool, "clear-only", "Run the M2 Vulkan clear demo") orelse false;
    const tracy = b.option([]const u8, "tracy-source", "Enable local profiling with a Tracy v0.12.2 source checkout");
    const options = b.addOptions();
    options.addOption(bool, "demo_2d", demo_2d);
    options.addOption(bool, "clear_only", clear_only);
    options.addOption(bool, "tracy", tracy != null and !demo_2d and !clear_only);

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
    const test_step = b.step("test", "Run core, SDL platform, and demo tests");
    if (!demo_2d and !clear_only) {
        if (tracy) |path| {
            const client: std.Build.LazyPath = .{ .cwd_relative = b.pathJoin(&.{ path, "public", "TracyClient.cpp" }) };
            exe.root_module.link_libcpp = true;
            exe.root_module.addCSourceFile(.{ .file = client, .flags = &.{
                "-std=c++17",           "-DTRACY_ENABLE",            "-DTRACY_ON_DEMAND",   "-DTRACY_ONLY_LOCALHOST",
                "-DTRACY_NO_BROADCAST", "-DTRACY_NO_SYSTEM_TRACING", "-DTRACY_NO_SAMPLING",
            } });
        }
        const physics_test = b.step("physics-test", "Exercise Jolt without a window or GPU");
        if (b.lazyDependency("jolt", .{})) |jolt| {
            const physics = configurePhysics(b, jolt, target, optimize);
            exe.root_module.addImport("jolt_c", physics.bindings);
            exe.root_module.linkLibrary(physics.library);
            const tests = b.addTest(.{ .root_module = b.createModule(.{
                .root_source_file = b.path("src/physics_test.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{.{ .name = "jolt_c", .module = physics.bindings }},
            }) });
            tests.root_module.linkLibrary(physics.library);
            physics_test.dependOn(&b.addRunArtifact(tests).step);
        }
        test_step.dependOn(physics_test);
        configureAssets(b, exe.root_module);
        if (b.lazyDependency("miniaudio", .{})) |miniaudio| {
            const app = exe.root_module;
            app.link_libc = true;
            app.addIncludePath(miniaudio.path("miniaudio-0.11.26"));
            app.addCSourceFile(.{ .file = b.path("src/engine/audio/miniaudio_bridge.c"), .flags = &.{"-std=c11"} });
        }
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

    test_step.dependOn(&exe.step);
    for ([_]*std.Build.Module{ core, platform, exe.root_module }) |module| {
        const tests = b.addTest(.{ .root_module = module });
        test_step.dependOn(&b.addRunArtifact(tests).step);
    }
}

/// 优化模式选择：显式 `-Doptimize` 优先；否则 `--release=<mode>` 使用对应模式；
/// 裸 `--release` 使用 ReleaseSafe；其余为 Debug。
fn optimizeOption(b: *std.Build) std.builtin.Optimize {
    if (b.option(std.builtin.Optimize, "optimize", "Prioritize performance, safety, or binary size")) |mode| {
        return mode;
    }
    const release_requested = (b.option(bool, "release", "optimize for end users") orelse false) or
        (b.graph.release_mode != .off);
    if (release_requested) {
        return switch (b.graph.release_mode) {
            .fast => .ReleaseFast,
            .safe => .ReleaseSafe,
            .small => .ReleaseSmall,
            .any, .off => .ReleaseSafe,
        };
    }
    return .Debug;
}

fn configurePhysics(b: *std.Build, jolt: *std.Build.Dependency, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) struct {
    library: *std.Build.Step.Compile,
    bindings: *std.Build.Module,
} {
    // Use the upstream core source list, without the optional object stream.
    b.dependOnFileContents(jolt.path("JoltPhysics-5.7.0/Jolt/Jolt.cmake"));
    const cmake = jolt.builder.root.root_dir.handle.readFileAlloc(b.graph.io, "JoltPhysics-5.7.0/Jolt/Jolt.cmake", b.allocator, .limited(128 * 1024)) catch |err|
        @panic(@errorName(err));
    const marker = "set(JOLT_PHYSICS_SRC_FILES\n";
    const start = (std.mem.indexOf(u8, cmake, marker) orelse @panic("Jolt source list missing")) + marker.len;
    const end = std.mem.indexOfScalarPos(u8, cmake, start, ')') orelse @panic("Jolt source list is incomplete");
    var files: std.ArrayList([]const u8) = .empty;
    var tokens = std.mem.tokenizeAny(u8, cmake[start..end], " \t\r\n");
    while (tokens.next()) |token| {
        const prefix = "${JOLT_PHYSICS_ROOT}/";
        if (std.mem.startsWith(u8, token, prefix) and std.mem.endsWith(u8, token, ".cpp")) {
            files.append(b.allocator, token[prefix.len..]) catch @panic("out of memory");
        }
    }
    if (files.items.len == 0) @panic("Jolt C++ source list is empty");
    const module = b.createModule(.{ .target = target, .optimize = optimize, .link_libcpp = true });
    module.addIncludePath(jolt.path("JoltPhysics-5.7.0"));
    const flags = &.{ "-std=c++17", "-fno-exceptions", "-fno-rtti", "-ffp-contract=off", "-fno-sanitize=undefined" };
    module.addCSourceFiles(.{ .root = jolt.path("JoltPhysics-5.7.0/Jolt"), .files = files.items, .flags = flags });
    module.addCSourceFile(.{ .file = b.path("src/engine/physics/jolt_bridge.cpp"), .flags = flags });
    const headers = b.addTranslateC(.{
        .root_source_file = b.path("src/engine/physics/jolt_bridge.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    return .{
        .library = b.addLibrary(.{ .name = "jolt", .linkage = .static, .root_module = module }),
        .bindings = headers.createModule(),
    };
}

fn configureAssets(b: *std.Build, app: *std.Build.Module) void {
    app.addAnonymousImport("demo.glb", .{ .root_source_file = b.path("assets/demo.glb") });
    app.addAnonymousImport("range.glb", .{ .root_source_file = b.path("assets/range.glb") });
    app.addAnonymousImport("DroidSansFallbackFull.ttf", .{ .root_source_file = b.path("assets/DroidSansFallbackFull.ttf") });
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
