//! SDL3 事件封装（M1 Platform）。
//!
//! 事件类型直接复用 sdl3 bindings 的 `Event` union(enum)，
//! 这里提供统一的轮询入口，避免业务层直接依赖 sdl3 模块名。

const sdl = @import("sdl3");

/// SDL 事件（透传）。
pub const Event = sdl.Event;

/// 事件类型枚举（透传）。
pub const EventType = sdl.EventType;

/// 窗口事件（透传）。
pub const WindowEvent = sdl.events.WindowEvent;
pub const pollRaw = sdl.events.pollRaw;
pub const fromRaw = sdl.events.fromRaw;

/// 轮询下一个事件；队列为空返回 null。
pub fn pollEvent() ?Event {
    return sdl.events.poll();
}

/// `pollEvent` 的别名，兼容不同调用习惯。
pub fn poll() ?Event {
    return pollEvent();
}

/// 是否存在某类事件。
pub fn has(event_type: EventType) bool {
    return sdl.events.has(event_type);
}

test "event module compiles" {
    _ = Event;
    _ = EventType;
    _ = WindowEvent;
    _ = pollEvent;
    _ = poll;
    _ = has;
}
