//! Vulkan 场景 Demo，复用 M1 平台事件循环和 M2 交换链。
const std = @import("std");
const platform = @import("engine.platform.sdl");
const sdl = @import("sdl3");
const Logger = @import("zigsdl3demo").Logger;
const GpuRenderer = @import("engine/renderer/gpu_renderer.zig").GpuRenderer;
const DemoScene = @import("engine/renderer/demo_scene.zig").DemoScene;
const options = @import("build_options");
const demo_2d = options.demo_2d;
const show_scene = !demo_2d and !options.clear_only;

const log = Logger.init(.info);

pub fn main(init: std.process.Init) !void {
    const model_path: ?[]const u8 = if (show_scene) path: {
        const args = try init.minimal.args.toSlice(init.arena.allocator());
        if (args.len > 2) {
            log.log(.error_, "demo", "用法: zigsdl3demo [scene.glb|scene.gltf]", .{});
            return error.InvalidArguments;
        }
        break :path if (args.len == 2) args[1] else null;
    } else null;
    platform.init() catch |err| {
        log.log(.error_, "sdl", "初始化失败: {s}", .{sdl.lastErrorText()});
        return err;
    };
    defer platform.deinit();

    const window = platform.window.createWithFlags("SDL3 Zig Demo", 800, 600, .{
        .resizable = true,
        .maximized = true,
        .high_pixel_density = true,
        .vulkan = !demo_2d,
    }) catch |err| {
        log.log(.error_, "sdl", "创建窗口失败: {s}", .{sdl.lastErrorText()});
        return err;
    };
    defer platform.window.destroy(window);

    const renderer = if (demo_2d)
        sdl.Renderer.init(window, null) catch |err| {
            log.log(.error_, "sdl", "创建 2D 渲染器失败: {s}", .{sdl.lastErrorText()});
            return err;
        }
    else
        try GpuRenderer.init(window);
    defer renderer.deinit();
    var scene = if (show_scene) DemoScene.init(renderer, init.gpa, init.io, model_path) catch |err| {
        log.log(.error_, "scene", "初始化失败 ({s}): {s}", .{ @errorName(err), sdl.lastErrorText() });
        return err;
    } else {};
    defer if (show_scene) scene.deinit();

    var vsync = true;
    if (demo_2d) renderer.setVSync(1) catch {
        vsync = false;
        log.log(.warn, "sdl", "无法启用 VSync，使用帧间延时: {s}", .{sdl.lastErrorText()});
    };

    const window_id = window.id();
    var input = platform.InputState.initWithWindow(window);
    const initial_flags = window.flags();
    var focused = initial_flags.input_focus;
    var minimized = initial_flags.minimized;
    var logical_size = try window.size();
    var pixel_size = try window.sizeInPixels();
    var mouse_offset = platform.MouseDelta{};
    var last_extent = GpuRenderer.Extent{ .width = 0, .height = 0 };
    var previous_ns = sdl.timer.ticksNs();

    if (demo_2d)
        log.log(.info, "demo", "WASD 移动，左键触发动作，Tab 捕获或释放鼠标，Esc 退出", .{})
    else if (show_scene and model_path == null)
        log.log(.info, "demo", "Tab 捕获鼠标，WASD 移动，左 Shift 冲刺，空格跳跃，左键开火，R 换弹，Esc 退出", .{})
    else if (show_scene)
        log.log(.info, "demo", "Tab 捕获鼠标，WASD/空格/Ctrl 飞行，Esc 退出", .{})
    else
        log.log(.info, "demo", "Vulkan 固定色清屏，Tab 捕获或释放鼠标，Esc 退出", .{});
    logSizes(logical_size, pixel_size);

    loop: while (true) {
        const now_ns = sdl.timer.ticksNs();
        const frame_seconds = @as(f32, @floatFromInt(now_ns - previous_ns)) / 1e9;
        previous_ns = now_ns;
        input.beginFrame();
        var size_changed = false;
        while (platform.event.pollRaw()) |raw_event| {
            if (show_scene) DemoScene.processEvent(&raw_event);
            const event = platform.event.fromRaw(raw_event);
            switch (event) {
                .quit => break :loop,
                .window => |e| {
                    if (e.window_id != window_id) continue;
                    switch (e.kind) {
                        .close_requested => break :loop,
                        .resized => |size| {
                            logical_size = size;
                            size_changed = true;
                        },
                        .pixel_size_changed => |size| {
                            pixel_size = size;
                            size_changed = true;
                        },
                        .restored, .maximized => minimized = false,
                        .focus_lost, .minimized => {
                            if (e.kind == .minimized) minimized = true else focused = false;
                            input.releaseAll();
                            if (input.mouseCaptured()) setCapture(&input, false);
                        },
                        .focus_gained => focused = true,
                        else => {},
                    }
                },
                .key_down => |e| {
                    if (e.window_id != window_id or !focused) continue;
                    if (e.scancode == .escape) break :loop;
                    if (e.scancode == .tab and !e.repeat and !minimized)
                        setCapture(&input, !input.mouseCaptured());
                },
                else => {},
            }
            if (focused and !minimized) input.handleEvent(event);
        }
        if (size_changed) logSizes(logical_size, pixel_size);
        if (minimized or pixel_size.width <= 0 or pixel_size.height <= 0) {
            sdl.timer.delay(40);
            continue;
        }

        if (demo_2d and focused and input.mouseCaptured()) {
            const delta = input.mouseDelta();
            const half_width = @as(f32, @floatFromInt(pixel_size.width)) / 2;
            const half_height = @as(f32, @floatFromInt(pixel_size.height)) / 2;
            mouse_offset.x = @min(half_width, @max(-half_width, mouse_offset.x + delta.x));
            mouse_offset.y = @min(half_height, @max(-half_height, mouse_offset.y + delta.y));
        }
        if (input.pressed(.fire)) log.log(.info, "input", "检测到左键按下", .{});

        if (demo_2d) {
            draw(renderer, pixel_size, &input, mouse_offset) catch |err| {
                log.log(.error_, "sdl", "绘制失败: {s}", .{sdl.lastErrorText()});
                return err;
            };
            if (!vsync) sdl.timer.delay(16);
        } else {
            const extent = if (show_scene)
                try scene.render(renderer, &input, frame_seconds)
            else
                try renderer.clear();
            if (extent) |size| {
                if (size.width != last_extent.width or size.height != last_extent.height) {
                    log.log(.info, "gpu", "已提交 {d}x{d} 帧", .{ size.width, size.height });
                    last_extent = size;
                }
            } else {
                sdl.timer.delay(16);
            }
        }
    }

    log.log(.info, "demo", "退出", .{});
}

test {
    _ = @import("engine/renderer/camera.zig");
    _ = @import("engine/renderer/render_queue.zig");
    if (show_scene) {
        _ = @import("engine/assets/gltf.zig");
        _ = @import("engine/renderer/lighting.zig");
    }
}

fn setCapture(input: *platform.InputState, captured: bool) void {
    input.setMouseCaptured(captured) catch {
        log.log(.warn, "input", "无法更改相对鼠标模式: {s}", .{sdl.lastErrorText()});
        return;
    };
    log.log(.info, "input", "相对鼠标模式: {s}", .{if (input.mouseCaptured()) "开启" else "关闭"});
}

fn logSizes(logical: sdl.Size, pixels: sdl.Size) void {
    log.log(.info, "window", "窗口 {d}x{d}，像素 {d}x{d}", .{
        logical.width, logical.height, pixels.width, pixels.height,
    });
}

fn draw(renderer: sdl.Renderer, size: sdl.Size, input: *const platform.InputState, offset: platform.MouseDelta) !void {
    const width: f32 = @floatFromInt(size.width);
    const height: f32 = @floatFromInt(size.height);
    const side = @min(100, @min(width, height));
    const dx: f32 = @floatFromInt(@as(i32, @intFromBool(input.isDown(.move_right))) -
        @as(i32, @intFromBool(input.isDown(.move_left))));
    const dy: f32 = @floatFromInt(@as(i32, @intFromBool(input.isDown(.move_back))) -
        @as(i32, @intFromBool(input.isDown(.move_forward))));
    const rect: sdl.FRect = .{
        .x = @min(width - side, @max(0, (width - side) / 2 + offset.x + dx * 32)),
        .y = @min(height - side, @max(0, (height - side) / 2 + offset.y + dy * 32)),
        .w = side,
        .h = side,
    };

    try renderer.setDrawColorFloat(.{ .r = 0.1, .g = 0.2, .b = 0.4, .a = 1.0 });
    try renderer.clear();
    try renderer.setDrawColorFloat(if (input.isDown(.fire) or input.pressed(.fire))
        .{ .r = 1.0, .g = 0.7, .b = 0.2, .a = 1.0 }
    else
        .{ .r = 1.0, .g = 0.2, .b = 0.2, .a = 1.0 });
    try renderer.fillRect(rect);
    try renderer.setDrawColorFloat(.{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 });
    try renderer.rect(rect);
    try renderer.present();
}
