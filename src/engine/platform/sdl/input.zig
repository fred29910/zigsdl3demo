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

/// 每帧按 beginFrame → handleEvent → 查询的顺序使用。
pub const InputState = struct {
    /// 当前帧各动作是否按下。
    down: [action_count]bool = @splat(false),
    pressed_this_frame: [action_count]bool = @splat(false),
    released_this_frame: [action_count]bool = @splat(false),
    /// 当前帧累积的鼠标增量。
    mouse_dx: f32 = 0,
    mouse_dy: f32 = 0,
    /// 关联窗口（用于捕获/释放鼠标）。
    window: ?Window = null,

    pub fn init() InputState {
        return .{};
    }

    pub fn initWithWindow(window: Window) InputState {
        return .{ .window = window };
    }

    /// 清空本帧边沿和鼠标增量，保留当前按住的动作。
    pub fn beginFrame(self: *InputState) void {
        self.pressed_this_frame = @splat(false);
        self.released_this_frame = @splat(false);
        self.mouse_dx = 0;
        self.mouse_dy = 0;
    }

    fn acceptsWindow(self: *const InputState, id: window_mod.WindowId) bool {
        const window = self.window orelse return true;
        return window.id() == id;
    }

    fn setDown(self: *InputState, action: Action, down: bool) void {
        const i = @backingInt(action);
        if (self.down[i] == down) return;
        self.down[i] = down;
        if (down) self.pressed_this_frame[i] = true else self.released_this_frame[i] = true;
    }

    /// 失焦时复位按住的动作，同时保留本帧已发生的边沿。
    pub fn releaseAll(self: *InputState) void {
        for (&self.down, &self.released_this_frame) |*down, *released_this_frame| {
            if (down.*) released_this_frame.* = true;
            down.* = false;
        }
        self.mouse_dx = 0;
        self.mouse_dy = 0;
    }

    /// 处理单个 SDL 事件，更新当前状态与鼠标增量。
    pub fn handleEvent(self: *InputState, event: sdl.Event) void {
        switch (event) {
            .key_down => |e| {
                if (!self.acceptsWindow(e.window_id) or e.repeat) return;
                if (keyToAction(e.scancode)) |action| self.setDown(action, true);
            },
            .key_up => |e| {
                if (!self.acceptsWindow(e.window_id)) return;
                if (keyToAction(e.scancode)) |action| self.setDown(action, false);
            },
            .mouse_motion => |e| {
                if (!self.acceptsWindow(e.window_id)) return;
                self.mouse_dx += e.xrel;
                self.mouse_dy += e.yrel;
            },
            .mouse_button_down => |e| {
                if (self.acceptsWindow(e.window_id) and e.button == .left) self.setDown(.fire, true);
            },
            .mouse_button_up => |e| {
                if (self.acceptsWindow(e.window_id) and e.button == .left) self.setDown(.fire, false);
            },
            else => {},
        }
    }

    pub fn isDown(self: *const InputState, action: Action) bool {
        return self.down[@backingInt(action)];
    }

    pub fn pressed(self: *const InputState, action: Action) bool {
        return self.pressed_this_frame[@backingInt(action)];
    }

    pub fn released(self: *const InputState, action: Action) bool {
        return self.released_this_frame[@backingInt(action)];
    }

    pub fn mouseDelta(self: *const InputState) MouseDelta {
        return .{ .x = self.mouse_dx, .y = self.mouse_dy };
    }

    /// SDL 相对模式负责捕获和光标可见性。
    pub fn setMouseCaptured(self: *InputState, captured: bool) !void {
        const window = self.window orelse return error.NoWindow;
        try window.setRelativeMouseMode(captured);
        self.mouse_dx = 0;
        self.mouse_dy = 0;
    }

    /// 当前是否处于鼠标捕获状态。
    pub fn mouseCaptured(self: *const InputState) bool {
        const window = self.window orelse return false;
        return window.relativeMouseMode();
    }
};

fn keyToAction(scancode: sdl.Scancode) ?Action {
    return switch (scancode) {
        .w => .move_forward,
        .s => .move_back,
        .a => .move_left,
        .d => .move_right,
        .space => .jump,
        .lshift => .sprint,
        .lctrl => .crouch,
        .r => .reload,
        .e => .interact,
        else => null,
    };
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

fn testKey(down: bool, repeat: bool) sdl.Event {
    const key: @FieldType(sdl.Event, "key_down") = .{
        .timestamp = 0,
        .window_id = 0,
        .which = 0,
        .scancode = .w,
        .key = .w,
        .mod = .{},
        .raw_code = 0,
        .down = down,
        .repeat = repeat,
    };
    return if (down) .{ .key_down = key } else .{ .key_up = key };
}

/// 供视角与失焦测试复用的鼠标相对位移事件。
fn testMouseMotion(xrel: f32, yrel: f32) sdl.Event {
    return .{ .mouse_motion = .{
        .timestamp = 0,
        .window_id = 0,
        .which = 0,
        .buttons = .{},
        .x = 0,
        .y = 0,
        .xrel = xrel,
        .yrel = yrel,
    } };
}

test "same-frame tap keeps both input edges" {
    var state = InputState.init();
    state.beginFrame();
    state.handleEvent(testKey(true, false));
    state.handleEvent(testKey(false, false));
    try std.testing.expect(!state.isDown(.move_forward));
    try std.testing.expect(state.pressed(.move_forward));
    try std.testing.expect(state.released(.move_forward));
    state.beginFrame();
    try std.testing.expect(!state.pressed(.move_forward));
    try std.testing.expect(!state.released(.move_forward));
}

test "pressed keys persist across frames, and repeats do not rearm on focus loss" {
    var state = InputState.init();
    state.handleEvent(testKey(true, false));
    state.beginFrame();
    try std.testing.expect(state.isDown(.move_forward));
    try std.testing.expect(!state.pressed(.move_forward));
    state.releaseAll();
    state.handleEvent(testKey(true, true));
    try std.testing.expect(!state.isDown(.move_forward));
    try std.testing.expect(state.released(.move_forward));
}

test "a fast left click maps to both fire edges" {
    var state = InputState.init();
    var button: sdl.events.MouseButton = .{
        .timestamp = 0,
        .window_id = 0,
        .which = 0,
        .button = .left,
        .down = true,
        .clicks = 1,
        .x = 0,
        .y = 0,
    };
    state.handleEvent(.{ .mouse_button_down = button });
    button.down = false;
    state.handleEvent(.{ .mouse_button_up = button });
    try std.testing.expect(state.pressed(.fire));
    try std.testing.expect(state.released(.fire));
    try std.testing.expect(!state.isDown(.fire));
}

test "mouse motion accumulates within a frame" {
    var state = InputState.init();
    const motion_event = testMouseMotion(3, -2);
    state.handleEvent(motion_event);
    state.handleEvent(motion_event);
    const d = state.mouseDelta();
    try std.testing.expectEqual(@as(f32, 6), d.x);
    try std.testing.expectEqual(@as(f32, -4), d.y);
    state.beginFrame();
    try std.testing.expectEqual(MouseDelta{}, state.mouseDelta());
}

test "capture failure without a window leaves capture disabled" {
    var state = InputState.init();
    try std.testing.expectError(error.NoWindow, state.setMouseCaptured(true));
    try std.testing.expect(!state.mouseCaptured());
}

test "releaseAll clears accumulated mouse delta on focus loss" {
    var state = InputState.init();
    state.handleEvent(testMouseMotion(12, -7));
    try std.testing.expectEqual(@as(f32, 12), state.mouseDelta().x);
    try std.testing.expectEqual(@as(f32, -7), state.mouseDelta().y);
    state.releaseAll();
    try std.testing.expectEqual(MouseDelta{}, state.mouseDelta());
}
