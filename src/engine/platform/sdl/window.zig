//! SDL3 Window 封装（M1 Platform）。
//!
//! 对 sdl3 bindings 的 `Window` 做薄封装：统一工厂函数、常用查询与状态设置，
//! 并把底层 SDL Window 暴露出来便于渲染器/输入模块使用。

const std = @import("std");
const sdl = @import("sdl3");

/// 底层 SDL 窗口类型（句柄，可自由拷贝）。
pub const Window = sdl.Window;

/// 窗口标志（透传）。
pub const WindowFlags = sdl.WindowFlags;

/// 窗口 ID（透传）。
pub const WindowId = sdl.video.WindowId;

/// 默认标志创建窗口。
pub fn create(title: [:0]const u8, width: i32, height: i32) !Window {
    return Window.init(title, width, height, .{});
}

/// 带标志创建窗口。
pub fn createWithFlags(title: [:0]const u8, width: i32, height: i32, flags: WindowFlags) !Window {
    return Window.init(title, width, height, flags);
}

/// 与 sdl3 风格一致的初始化入口（透传）。
pub fn init(title: [:0]const u8, width: i32, height: i32, flags: WindowFlags) !Window {
    return Window.init(title, width, height, flags);
}

/// 销毁窗口（透传，便于函数式调用）。
pub fn destroy(window: Window) void {
    window.deinit();
}

test "window module compiles" {
    _ = Window;
    _ = WindowFlags;
    _ = WindowId;
    _ = create;
    _ = createWithFlags;
    _ = init;
    _ = destroy;
}