const std = @import("std");
const c = @cImport({
    @cInclude("SDL3/SDL.h");
});

pub fn main() !void {
    // 初始化 SDL
    if (!c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_EVENTS)) {
        std.debug.print("SDL_Init 失败: {s}\n", .{c.SDL_GetError()});
        return error.SDLInitFailed;
    }
    defer c.SDL_Quit();

    // 创建窗口
    const window_width: i32 = 800;
    const window_height: i32 = 600;

    const window = c.SDL_CreateWindow(
        "SDL3 Zig Demo",
        window_width,
        window_height,
        0,
    ) orelse {
        std.debug.print("SDL_CreateWindow 失败: {s}\n", .{c.SDL_GetError()});
        return error.SDLCreateWindowFailed;
    };
    defer c.SDL_DestroyWindow(window);

    // 创建渲染器
    const renderer = c.SDL_CreateRenderer(window, null) orelse {
        std.debug.print("SDL_CreateRenderer 失败: {s}\n", .{c.SDL_GetError()});
        return error.SDLCreateRendererFailed;
    };
    defer c.SDL_DestroyRenderer(renderer);

    std.debug.print("SDL3 Demo 启动成功!\n", .{});
    std.debug.print("窗口大小: {d}x{d}\n", .{ window_width, window_height });
    std.debug.print("按 ESC 键或点击关闭按钮退出\n", .{});

    // 主事件循环
    var running = true;
    var event: c.SDL_Event = undefined;

    while (running) {
        // 处理事件
        while (c.SDL_PollEvent(&event)) {
            switch (event.type) {
                c.SDL_EVENT_QUIT => {
                    running = false;
                },
                c.SDL_EVENT_KEY_DOWN => {
                    if (event.key.key == c.SDLK_ESCAPE) {
                        running = false;
                    }
                },
                else => {},
            }
        }

        // 清屏为深蓝色
        _ = c.SDL_SetRenderDrawColorFloat(renderer, 0.1, 0.2, 0.4, 1.0);
        _ = c.SDL_RenderClear(renderer);

        // 绘制一个红色的矩形
        _ = c.SDL_SetRenderDrawColorFloat(renderer, 1.0, 0.2, 0.2, 1.0);
        const rect = c.SDL_FRect{
            .x = @floatFromInt(window_width / 2 - 50),
            .y = @floatFromInt(window_height / 2 - 50),
            .w = 100,
            .h = 100,
        };
        _ = c.SDL_RenderFillRect(renderer, &rect);

        // 绘制白色边框
        _ = c.SDL_SetRenderDrawColorFloat(renderer, 1.0, 1.0, 1.0, 1.0);
        _ = c.SDL_RenderRect(renderer, &rect);

        // 呈现画面
        _ = c.SDL_RenderPresent(renderer);
    }

    std.debug.print("SDL3 Demo 退出\n", .{});
}

