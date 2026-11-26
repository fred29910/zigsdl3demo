//! 游戏大厅的纯逻辑状态机（Spec Kit 001-game-lobby-ui）。
//! 仅持有会话状态与设置值，不涉及渲染/IO；UI 与 main 循环负责调用。

const std = @import("std");

pub const View = enum { lobby, training, preview, viewer, demo_2d, clear_only };
pub const Settings = struct { sensitivity: f32 = 1.0, volume: u8 = 100 };
pub const Session = struct {
    view: View = .lobby,
    last_mode: ?View = null,
    settings: Settings = .{},
    notice: ?[]const u8 = null,
    pending: ?View = null,
    cooldown_until_ns: u64 = 0,
};

pub fn clampSensitivity(v: f32) f32 {
    var x = v;
    if (x < 0.5) x = 0.5;
    if (x > 2.0) x = 2.0;
    return @round(x * 20.0) / 20.0;
}

pub fn clampVolume(v: i32) u8 {
    if (v < 0) return 0;
    if (v > 100) return 100;
    return @intCast(v);
}

pub fn confirm(s: *Session, view: View, now_ns: u64) bool {
    if (now_ns < s.cooldown_until_ns) return false;
    s.pending = view;
    return true;
}

pub fn beginMode(s: *Session) void {
    if (s.pending) |p| {
        s.view = p;
        s.last_mode = p;
        s.pending = null;
    }
}

pub fn returnToLobby(s: *Session) void {
    s.view = .lobby;
    s.pending = null;
    s.notice = null;
}

pub fn setNotice(s: *Session, msg: []const u8) void {
    s.notice = msg;
}

test "default session view and settings" {
    const s = Session{};
    try std.testing.expectEqual(View.lobby, s.view);
    try std.testing.expectEqual(@as(f32, 1.0), s.settings.sensitivity);
    try std.testing.expectEqual(@as(u8, 100), s.settings.volume);
}

test "clampSensitivity bounds and step" {
    try std.testing.expectEqual(@as(f32, 0.5), clampSensitivity(-1));
    try std.testing.expectEqual(@as(f32, 2.0), clampSensitivity(9.9));
    try std.testing.expectApproxEqAbs(@as(f32, 1.25), clampSensitivity(1.234), 0.0001);
}

test "clampVolume bounds" {
    try std.testing.expectEqual(@as(u8, 0), clampVolume(-5));
    try std.testing.expectEqual(@as(u8, 100), clampVolume(150));
}

test "confirm last wins before init" {
    var s = Session{};
    const now: u64 = 1000;
    try std.testing.expect(confirm(&s, .training, now));
    try std.testing.expect(confirm(&s, .preview, now));
    try std.testing.expect(s.pending != null);
    try std.testing.expectEqual(View.preview, s.pending.?);
}

test "confirm respects cooldown" {
    var s = Session{};
    s.cooldown_until_ns = 2000;
    try std.testing.expect(!confirm(&s, .training, 1000));
    try std.testing.expect(s.pending == null);
}

test "beginMode moves pending to view" {
    var s = Session{};
    _ = confirm(&s, .training, 0);
    beginMode(&s);
    try std.testing.expectEqual(View.training, s.view);
    try std.testing.expect(s.pending == null);
    try std.testing.expectEqual(@as(?View, .training), s.last_mode);
}

test "returnToLobby clears notice keeps settings" {
    var s = Session{
        .view = .training,
        .notice = "err",
        .pending = .preview,
        .settings = .{ .sensitivity = 1.5, .volume = 42 },
    };
    returnToLobby(&s);
    try std.testing.expectEqual(View.lobby, s.view);
    try std.testing.expect(s.pending == null);
    try std.testing.expect(s.notice == null);
    try std.testing.expectEqual(@as(f32, 1.5), s.settings.sensitivity);
    try std.testing.expectEqual(@as(u8, 42), s.settings.volume);
}

test "setNotice stores message" {
    var s = Session{};
    setNotice(&s, "hi");
    try std.testing.expect(s.notice != null);
    try std.testing.expectEqualStrings("hi", s.notice.?);
}