//! SDL3 Zig Demo — demo 窗口用新版 SDL bindings（https://github.com/fred29910/sdl3-zig）
//! 替换原来的 @cImport 方式。
const std = @import("std");
const sdl = @import("sdl3");

pub fn main() !void {
    sdl.init(.{ .video = true, .events = true }) catch |err| {
        std.debug.print("SDL 初始化失败: {s}\n", .{sdl.lastErrorText()});
        return err;
    };
    defer sdl.quit();

    const window_width: i32 = 800;
    const window_height: i32 = 600;

    const both = try sdl.createWindowAndRenderer("SDL3 Zig Demo", window_width, window_height, .{});
    defer both.renderer.deinit();
    defer both.window.deinit();

    const window = both.window;
    const renderer = both.renderer;

    std.debug.print("SDL3 Demo 启动成功!\n", .{});
    std.debug.print("窗口大小: {d}x{d}\n", .{ window_width, window_height });
    std.debug.print("按 ESC 键或点击关闭按钮退出\n", .{});

    // 主事件循环
    main: while (true) {
        while (sdl.events.poll()) |event| switch (event) {
            .quit => break :main,
            .window => |e| if (e.kind == .close_requested or e.window_id != window.id()) break :main,
            .key_down => |e| if (e.key == .escape) break :main,
            else => {},
        };

        // 清屏为深蓝色
        try renderer.setDrawColorFloat(.{ .r = 0.1, .g = 0.2, .b = 0.4, .a = 1.0 });
        try renderer.clear();

        // 绘制一个红色的矩形
        try renderer.setDrawColorFloat(.{ .r = 1.0, .g = 0.2, .b = 0.2, .a = 1.0 });
        const rect: sdl.FRect = .{
            .x = @floatFromInt(window_width / 2 - 50),
            .y = @floatFromInt(window_height / 2 - 50),
            .w = 100,
            .h = 100,
        };
        try renderer.fillRect(rect);

        // 绘制白色边框
        try renderer.setDrawColorFloat(.{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 });
        try renderer.rect(rect);

        // 呈现画面
        try renderer.present();
    }

    std.debug.print("SDL3 Demo 退出\n", .{});
}
