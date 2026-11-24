//! SDL3 输入封装（M1 Platform）。
//!
//! 提供 Action 映射与 InputState：键盘/鼠标状态、边沿检测、鼠标增量与捕获。

const std = @import("std");
const sdl = @import("sdl3");
const window_mod = @import("window.zig");

pub const Window = window_mod.Window;

/// 逻辑动作（与具体按键解耦）。
pub const Action = enum {
    move_forward,
    move_back,
    move_left,
    move_right,
    jump,
    sprint,
    crouch,
    fire,
    reload,
    interact,
};

const action_count = @typeInfo(Action).@"enum".field_names.len;

/// 鼠标增量。
pub const MouseDelta = struct {
    x: f32 = 0,
    y: f32 = 0,
};

/// 输入状态。
pub const InputState = struct {
    /// 当前帧各动作是否按下。
    down: [action_count]bool = @splat(false),
    /// 上一帧各动作是否按下（用于边沿检测）。
    prev: [action_count]bool = @splat(false),
    /// 当前帧累积的鼠标增量。
    mouse_dx: f32 = 0,
    mouse_dy: f32 = 0,
    /// 鼠标是否被捕获（相对模式）。
    captured: bool = false,
    /// 关联窗口（用于捕获/释放鼠标）。
    window: ?Window = null,

    pub fn init() InputState {
        return .{};
    }

    pub fn initWithWindow(window: Window) InputState {
        var state = InputState{};
        state.window = window;
        return state;
    }

    pub fn setWindow(self: *InputState, window: Window) void {
        self.window = window;
    }

    /// 开始新一帧：保存上一帧状态并清空鼠标增量。
    pub fn beginFrame(self: *InputState) void {
        self.prev = self.down;
        self.mouse_dx = 0;
        self.mouse_dy = 0;
    }

    /// `beginFrame` 的别名。
    pub fn resetFrame(self: *InputState) void {
        self.beginFrame();
    }

    /// 处理单个 SDL 事件，更新当前状态与鼠标增量。
    pub fn handleEvent(self: *InputState, event: sdl.Event) void {
        switch (event) {
            .key_down => |e| {
                if (keyToAction(e.scancode)) |action| {
                    self.down[@intFromEnum(action)] = true;
                }
            },
            .key_up => |e| {
                if (keyToAction(e.scancode)) |action| {
                    self.down[@intFromEnum(action)] = false;
                }
            },
            .mouse_motion => |e| {
                self.mouse_dx += e.xrel;
                self.mouse_dy += e.yrel;
            },
            .mouse_button_down => |e| {
                if (mouseButtonToAction(e.button)) |action| {
                    self.down[@intFromEnum(action)] = true;
                }
            },
            .mouse_button_up => |e| {
                if (mouseButtonToAction(e.button)) |action| {
                    self.down[@intFromEnum(action)] = false;
                }
            },
            else => {},
        }
    }

    /// 轮询 SDL 当前状态，刷新本帧输入（适合每帧调用）。
    pub fn update(self: *InputState) void {
        self.beginFrame();

        const ks = sdl.keyboard.state();
        inline for (0..action_count) |i| {
            const action: Action = @enumFromInt(i);
            if (action == .fire) continue;
            const sc = scancodeFor(action);
            self.down[i] = ks.isDown(sc);
        }

        const ms = sdl.mouse.relativeState();
        self.mouse_dx = ms.x;
        self.mouse_dy = ms.y;

        const button_state = sdl.mouse.state().buttons;
        self.down[@intFromEnum(Action.fire)] = button_state.isDown(.left);
    }

    pub fn isDown(self: *const InputState, action: Action) bool {
        return self.down[@intFromEnum(action)];
    }

    pub fn pressed(self: *const InputState, action: Action) bool {
        const idx = @intFromEnum(action);
        return self.down[idx] and !self.prev[idx];
    }

    pub fn released(self: *const InputState, action: Action) bool {
        const idx = @intFromEnum(action);
        return !self.down[idx] and self.prev[idx];
    }

    pub fn mouseDelta(self: *const InputState) MouseDelta {
        return .{ .x = self.mouse_dx, .y = self.mouse_dy };
    }

    /// 设置鼠标捕获状态；若已关联窗口，则同步到 SDL 相对模式。
    pub fn setMouseCaptured(self: *InputState, captured: bool) void {
        self.captured = captured;
        if (self.window) |window| {
            window.setRelativeMouseMode(captured) catch {};
            if (captured) {
                sdl.mouse.hideCursor() catch {};
            } else {
                sdl.mouse.showCursor() catch {};
            }
        }
    }

    /// 显式指定窗口的鼠标捕获设置。
    pub fn setMouseCapturedWindow(self: *InputState, window: Window, captured: bool) !void {
        self.window = window;
        self.captured = captured;
        try window.setRelativeMouseMode(captured);
        if (captured) {
            try sdl.mouse.hideCursor();
        } else {
            try sdl.mouse.showCursor();
        }
    }

    /// 当前是否处于鼠标捕获状态。
    pub fn mouseCaptured(self: *const InputState) bool {
        return self.captured;
    }
};

fn scancodeFor(action: Action) sdl.Scancode {
    return switch (action) {
        .move_forward => .w,
        .move_back => .s,
        .move_left => .a,
        .move_right => .d,
        .jump => .space,
        .sprint => .lshift,
        .crouch => .lctrl,
        .reload => .r,
        .interact => .e,
        .fire => .unknown,
    };
}

fn keyToAction(scancode: sdl.Scancode) ?Action {
    inline for (0..action_count) |i| {
        const action: Action = @enumFromInt(i);
        if (action == .fire) continue;
        if (scancodeFor(action) == scancode) return action;
    }
    return null;
}

fn mouseButtonToAction(button: sdl.mouse.Button) ?Action {
    return if (button == .left) Action.fire else null;
}

test "action enum count" {
    try std.testing.expectEqual(@as(usize, 10), action_count);
}

test "input state defaults" {
    var state = InputState.init();
    try std.testing.expect(!state.isDown(.move_forward));
    try std.testing.expect(!state.pressed(.jump));
    try std.testing.expect(!state.released(.fire));
    const d = state.mouseDelta();
    try std.testing.expectEqual(@as(f32, 0), d.x);
    try std.testing.expectEqual(@as(f32, 0), d.y);
    try std.testing.expect(!state.mouseCaptured());
}

test "input edge detection" {
    var state = InputState.init();
    state.down[@intFromEnum(Action.jump)] = true;
    state.prev[@intFromEnum(Action.jump)] = false;
    try std.testing.expect(state.pressed(.jump));
    try std.testing.expect(!state.released(.jump));

    state.prev[@intFromEnum(Action.jump)] = true;
    state.down[@intFromEnum(Action.jump)] = false;
    try std.testing.expect(state.released(.jump));
}

test "input handleEvent" {
    var state = InputState.init();
    const key_event: sdl.Event = .{ .key_down = .{
        .timestamp = 0,
        .window_id = 0,
        .which = 0,
        .scancode = .w,
        .key = .escape,
        .mod = .{},
        .raw_code = 0,
        .down = true,
        .repeat = false,
    } };
    state.handleEvent(key_event);
    try std.testing.expect(state.isDown(.move_forward));

    const motion_event: sdl.Event = .{ .mouse_motion = .{
        .timestamp = 0,
        .window_id = 0,
        .which = 0,
        .buttons = .{},
        .x = 0,
        .y = 0,
        .xrel = 3,
        .yrel = -2,
    } };
    state.handleEvent(motion_event);
    const d = state.mouseDelta();
    try std.testing.expectEqual(@as(f32, 3), d.x);
    try std.testing.expectEqual(@as(f32, -2), d.y);

    state.setMouseCaptured(false);
    try std.testing.expect(!state.mouseCaptured());
}