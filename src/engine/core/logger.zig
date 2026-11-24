//! Logger 模块：按级别/模块输出调试日志到 stderr。
//!
//! 提供可过滤的级别、模块标签与格式化上下文，便于单元测试与运行时调试。

const std = @import("std");

/// 日志级别，数值越大优先级越高。
pub const Level = enum(u8) {
    debug,
    info,
    warn,
    error_,
};

/// 将级别转换为可读名称。
pub fn levelName(level: Level) []const u8 {
    return switch (level) {
        .debug => "DEBUG",
        .info => "INFO",
        .warn => "WARN",
        .error_ => "ERROR",
    };
}

/// Logger：持有最低输出级别，按级别过滤并格式化输出到 stderr。
pub const Logger = struct {
    /// 最低输出级别（低于此级别的消息被过滤）。
    level: Level = .info,

    /// 以指定最低级别创建 Logger；默认级别为 info。
    pub fn init(level: Level) Logger {
        return .{ .level = level };
    }

    /// 判断给定级别是否会被输出。
    pub fn enabled(self: Logger, level: Level) bool {
        return @intFromEnum(level) >= @intFromEnum(self.level);
    }

    /// 将一条日志格式化写入 `buf`，返回已写入的切片（含换行）。
    /// 不进行级别过滤，便于单测验证格式。
    pub fn format(
        self: Logger,
        buf: []u8,
        level: Level,
        module: []const u8,
        comptime fmt: []const u8,
        args: anytype,
    ) ![]u8 {
        _ = self;
        var w = std.Io.Writer.fixed(buf);
        try w.print("[{s}] {s}: " ++ fmt ++ "\n", .{ levelName(level), module } ++ args);
        return w.buffered();
    }

    /// 按级别过滤并输出日志到 stderr。
    pub fn log(
        self: Logger,
        level: Level,
        module: []const u8,
        comptime fmt: []const u8,
        args: anytype,
    ) void {
        if (!self.enabled(level)) return;
        var buf: [1024]u8 = undefined;
        const line = self.format(&buf, level, module, fmt, args) catch return;
        std.debug.print("{s}", .{line});
    }

    /// 直接向 stderr 输出一段文本（不受级别过滤）。
    pub fn print(self: Logger, comptime fmt: []const u8, args: anytype) void {
        _ = self;
        std.debug.print(fmt, args);
    }
};

test "logger level filtering" {
    const l = Logger.init(.warn);
    try std.testing.expect(!l.enabled(.debug));
    try std.testing.expect(!l.enabled(.info));
    try std.testing.expect(l.enabled(.warn));
    try std.testing.expect(l.enabled(.error_));
}

test "logger format" {
    var buf: [256]u8 = undefined;
    const l = Logger.init(.debug);
    const line = try l.format(&buf, .info, "core", "hello {d}", .{42});
    try std.testing.expectEqualStrings("[INFO] core: hello 42\n", line);
}