//! SDL Platform facade（M1）。
//!
//! 重导出 window / event / input 子模块，统一作为 `engine.platform.sdl` 模块暴露。

const sdl = @import("sdl3");

pub fn init() !void {
    try sdl.init(.{ .video = true, .events = true });
}

pub const deinit = sdl.quit;

pub const window = @import("sdl/window.zig");
pub const event = @import("sdl/event.zig");
pub const input = @import("sdl/input.zig");

// 常用类型快捷重导出。
pub const Window = window.Window;
pub const WindowFlags = window.WindowFlags;
pub const WindowId = window.WindowId;
pub const Event = event.Event;
pub const EventType = event.EventType;
pub const InputState = input.InputState;
pub const Action = input.Action;
pub const MouseDelta = input.MouseDelta;

test "sdl facade compiles" {
    _ = window;
    _ = event;
    _ = input;
    _ = Window;
    _ = Event;
    _ = InputState;
    _ = Action;
}
