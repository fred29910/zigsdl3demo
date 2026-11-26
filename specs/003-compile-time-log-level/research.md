# Phase 0 Research: 编译期发布模式日志过滤

**Feature**: `003-compile-time-log-level`
**Date**: 2026-11-26
**Spec**: [spec.md](spec.md)

## 决策总览

- **Decision**: 保留现有自定义 `Logger`，不迁移到 `std.log`。
- **Rationale**: 当前项目已有 `debug/info/warn/error_`、运行时最低级别、`[LEVEL] module: message` stderr 输出与单元测试；70+ 调用点使用 `log.log(...)`。迁移 `std.log` 会改变 scope/module、级别名 `error_`、格式与 API，违反增量/零回归。
- **Alternatives considered**:
  - **完全改用 `std.log` + `std_options.log_level` + `logFn`**: Zig 原生 comptime 过滤与可定制输出，但需大规模改调用点、scope、格式与测试，超出本特性范围。
  - **仅靠 `builtin.mode` + `std.debug.print`**: 简单但破坏现有 `Logger` API、运行时过滤与测试。
  - **新增 `-Dlog-level` / 运行时环境变量**: 不符合 FR-004/FR-011，发布模式不能重新打开 debug；拒绝。

## Evidence: 当前项目

- `src/engine/core/logger.zig`：
  - `pub const Level = enum(u8) { debug, info, warn, error_ }`；数值越大优先级越高。
  - `pub const Logger = struct { level: Level = .info, ... }`。
  - `pub fn init(level: Level) Logger`；`pub fn enabled(self, level) bool`。
  - `pub fn format(...)` 输出 `[{LEVEL}] {module}: {fmt}\n`。
  - `pub fn log(...)` 先 `if (!self.enabled(level)) return;`，再 `std.debug.print`。
  - `pub fn print(...)` **不受级别过滤**；输出直接 `std.debug.print`。
  - 当前没有 `.log(.debug, ...)` 调用点；没有 `std.log` / `std_options`。
- `src/root.zig`：`pub const Logger = logger.Logger;`，核心模块对外暴露 `Logger`。
- 调用点：`src/main.zig`、`src/engine/assets/asset_manager.zig`、`src/engine/assets/gltf.zig`、`src/engine/renderer/gpu_renderer.zig`、`src/engine/renderer/demo_scene.zig`；均 `Logger.init(.info)` + `.log(.info/.warn/.error_, ...)`。
- `build.zig`：`const optimize = b.standardOptimizeOption(.{});`；Zig `0.17.1`；无 `preferred_optimize_mode`；两种基础演示模式 `-Ddemo-2d=true` / `-Dclear-only=true` 必须独立构建/测试；版本与依赖锁定不可改。
- 文档/验收：README 与 AGENTS 使用 `-Doptimize=ReleaseSafe`；宪法要求 `zig build install test`、发布模式复测、两种基础模式可独立构建/测试、文档中文、不破坏验收基线。

## Evidence: Zig 0.17.1

本环境 `zig version` = `0.17.1`；标准库路径 `/usr/local/zig/lib/std`。

### Optimize / `--release`

- `/usr/local/zig/lib/std/Build.zig` `StandardOptimizeOptionOptions`：`preferred_optimize_mode: ?std.builtin.Optimize = null`。
- `/usr/local/zig/lib/std/Build.zig` `pub fn standardOptimizeOption(...) std.builtin.Optimize`：
  1. 若 `preferred_optimize_mode` 非空：当 `-Drelease`/`--release` 为真或 `graph.release_mode != .off` 时返回 preferred mode，否则 `.debug`；
  2. 否则读取 `-Doptimize` / `--optimize`；
  3. 否则 `switch(graph.release_mode)`：`.off => .debug`；`.any` => 打印 `the project does not declare a preferred optimization mode. choose: --release=fast, --release=safe, or --release=small` 并退出；`.fast/.safe/.small` => 对应 mode。
- `zig build --help`：`--release[=mode] Request release mode, optionally specifying a preferred mode`；`-Doptimize=[enum] Prioritize performance, safety, or binary size`。
- `/usr/local/zig/lib/std/lang.zig`：`pub const Optimize = enum { debug, safe, fast, small, ... }`；兼容别名 `.Debug` / `.ReleaseSafe` / `.ReleaseFast` / `.ReleaseSmall`；`OptimizeMode` 已标记 deprecated alias；`fromString` 同时接受 `Debug/ReleaseSafe/ReleaseFast/ReleaseSmall` 与 `debug/safe/fast/small`。
- `/usr/local/zig/lib/std/std.zig`：`@import("builtin").mode`；`std.log.default_level`：`builtin.mode == .debug => .debug`，其余 `.info`。

**实测（当前项目，未改代码）**：
- `zig build --release --verbose`：**失败** `the project does not declare a preferred optimization mode. choose: --release=fast, --release=safe, or --release=small`。
- `zig build -Doptimize=ReleaseSafe --summary none`：**成功** exit 0。
- `zig build --release --summary none` 在未设 `preferred_optimize_mode` 前不能作为已验证路径。

**Decision**: `builtin.mode != .debug` 作为“发布构建”判定，不解析 `--release` 字符串；但 **`build.zig` 必须让裸 `zig build --release` 在 Zig 0.17.1 下得到非 Debug**。保留 `-Doptimize=...`。不改变 Zig 版本，不新增运行时日志开关。

## Evidence: `std.log` 仅作对照

- `/usr/local/zig/lib/std/std.zig`：`std_options` 可声明；`log_level` 字段；`logFn` 字段默认 `log.defaultLog`。
- `/usr/local/zig/lib/std/log.zig`：
  - `logEnabled(comptime level, comptime scope) bool`；
  - `log(comptime level, comptime scope, comptime format, args)`：`if (comptime !logEnabled(level, scope)) return;`；
  - `default_level` 与 `log_scope_levels`。
- `std.log` **未被当前项目使用**；本特性不需要设置 `std_options`，也不改 `std.debug.print` 以外的输出路径。

**Inference / limitation**: Zig 没有任意函数参数惰性求值宏。即使 logger 内部 comptime 丢弃输出，调用点参数在进入函数前已求值。要严格满足 FR-005，计划要求：
- `.debug` 参数无副作用；
- 任何昂贵/可能有副作用的 debug 参数必须在调用点用 `if (Logger.enabledComptime(.debug))` 或等价 `comptime` guard 包住；
- 对 comptime 已过滤调用，验证无输出、无格式化、无调用点额外开销；不能仅凭代码审查声明，需 release 下反证测试。

当前没有 `.debug` 调用点，新增测试将显式构造该场景。

## FR-009 处理 `print`

- `Logger.print` 当前不受过滤且未使用。
- **Decision**: 关闭 release 绕过路径：要么移除 `print`（当前无调用点），要么将其定义为“非日志 raw output”并在 release 下不输出低于 info；本特性选择**移除/禁用未过滤 `Logger.print`**，不保留 release 下低于 info 的日志通道。
- `Logger.log` 内部所有 `std.debug.print` 都位于 comptime 已放行分支；过滤后不输出。

## 运行时下限

- 编译期下限 `compile_time_min_level = if (release_mode) .info else .debug`。
- 现有 `Logger.init(level)` 保留；runtime `level` 只能**提高**阈值，不能降到编译期下限以下；`enabled(level)` 必须 `level >= effective_min_level`。
- release 下 `.debug` 永远不可重新打开；非 release `.debug` 可输出，但 `Logger.init(.info)` 这类显式 runtime 阈值仍可把该 logger 限制为 info，符合 FR-008。
- 现有 `Logger.init(.info)` 输出不得改变；非 release 新增 `.debug` 需使用 `Logger.init(.debug)` 或等价 effective level。

## Unknowns

- 无阻塞性 `NEEDS CLARIFICATION`。
- 不依赖外部服务、网络、数据库、shader、新依赖。
- 实现阶段才验证 Zig DCE 细节与字节级日志回归；本 Phase 0 不声称已实现。
