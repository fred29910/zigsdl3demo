//! Logger 模块：按级别/模块输出调试日志到 stderr。
//!
//! 提供可过滤的级别、模块标签与格式化上下文，便于单元测试与运行时调试。

const std = @import("std");
const builtin = @import("builtin");

/// 当前构建是否为发布构建（任何非 Debug 优化模式）。
pub const release_mode = builtin.mode != .debug;

/// 日志级别，数值越大优先级越高。
pub const Level = enum(u8) {
    debug,
    info,
    warn,
    error_,
};

/// 编译期最低输出级别：发布构建为 info，非发布构建为 debug。
pub const compile_time_min_level: Level = if (release_mode) .info else .debug;

/// 编译期判断某级别是否可能被输出；用于保护昂贵或有副作用的调用参数。
pub fn enabledComptime(level: Level) bool {
    return @backingInt(level) >= @backingInt(compile_time_min_level);
}

/// 运行时级别只能提高阈值，不能降低到编译期下限以下。
pub fn effectiveMinLevel(runtime_level: Level) Level {
    return if (enabledComptime(runtime_level)) runtime_level else compile_time_min_level;
}

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

    /// 判断给定级别是否会被输出（运行时阈值不得低于编译期下限）。
    pub fn enabled(self: Logger, level: Level) bool {
        return @backingInt(level) >= @backingInt(effectiveMinLevel(self.level));
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
    /// `level` 为 comptime 参数，发布构建下的 `.debug` 调用在编译期被丢弃。
    pub fn log(
        self: Logger,
        comptime level: Level,
        module: []const u8,
        comptime fmt: []const u8,
        args: anytype,
    ) void {
        if (comptime !enabledComptime(level)) return;
        if (!self.enabled(level)) return;
        var buf: [1024]u8 = undefined;
        const line = self.format(&buf, level, module, fmt, args) catch {
            std.debug.print("[{s}] {s}: " ++ fmt ++ "\n", .{ levelName(level), module } ++ args);
            return;
        };
        std.debug.print("{s}", .{line});
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

test "level ordering and names" {
    try std.testing.expect(@backingInt(Level.debug) < @backingInt(Level.info));
    try std.testing.expect(@backingInt(Level.info) < @backingInt(Level.warn));
    try std.testing.expect(@backingInt(Level.warn) < @backingInt(Level.error_));
    try std.testing.expectEqualStrings("DEBUG", levelName(.debug));
    try std.testing.expectEqualStrings("INFO", levelName(.info));
    try std.testing.expectEqualStrings("WARN", levelName(.warn));
    try std.testing.expectEqualStrings("ERROR", levelName(.error_));
}

test "compile-time minimum level" {
    try std.testing.expectEqual(if (release_mode) Level.info else Level.debug, compile_time_min_level);
    try std.testing.expectEqual(!release_mode, enabledComptime(.debug));
    try std.testing.expect(enabledComptime(.info));
    try std.testing.expect(enabledComptime(.warn));
    try std.testing.expect(enabledComptime(.error_));
}

test "effective minimum clamps runtime level" {
    try std.testing.expectEqual(compile_time_min_level, effectiveMinLevel(.debug));
    try std.testing.expectEqual(Level.warn, effectiveMinLevel(.warn));

    const debug_logger = Logger.init(.debug);
    try std.testing.expectEqual(!release_mode, debug_logger.enabled(.debug));
    try std.testing.expect(debug_logger.enabled(.info));

    const info_logger = Logger.init(.info);
    try std.testing.expect(!info_logger.enabled(.debug));
    try std.testing.expect(info_logger.enabled(.info));
}

test "guarded debug args follow compile-time floor" {
    var calls: usize = 0;
    if (comptime enabledComptime(.debug)) calls += 1;
    const expected: usize = if (release_mode) 0 else 1;
    try std.testing.expectEqual(expected, calls);
}
