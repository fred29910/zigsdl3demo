# Data Model: 编译期发布模式日志过滤

**Feature**: `003-compile-time-log-level`
**Date**: 2026-11-26
**Source spec**: [spec.md](spec.md)

本特性不引入持久化数据、网络数据或新外部实体；数据模型是日志级别与构建模式之间的不变量。

## Entities

### LogLevel（现有 `Logger.Level`）

- **Fields / values**: `debug`, `info`, `warn`, `error_`；数值 `debug=0 < info=1 < warn=2 < error_=3`。
- **Ordering**: 输出级别 `level >= effective_min_level` 时可输出。
- **Canonical names**: 日志文本 `[DEBUG]`, `[INFO]`, `[WARN]`, `[ERROR]`；Zig tag 现有 `error_` 不改。
- **Relationships**: `BuildMode` 决定 `compile_time_min_level`；`runtime_min_level` 与编译期下限组合成 `effective_min_level`。
- **Validation**: release 下 `effective_min_level >= info`；非 release 下 `effective_min_level >= debug`；runtime 不能低于编译期下限。

### BuildMode

- **Values**: `debug`（非发布）或 `release`（任何非 Debug optimization）。
- **Source**: `@import("builtin").mode != .debug`；`zig build --release`, `--release=fast/safe/small`, `-Doptimize=ReleaseSafe/ReleaseFast/ReleaseSmall` 最终进入 release；默认 `debug`。
- **Output**: `release_mode: bool`；`compile_time_min_level`。
- **Validation**: 不区分 release 子模式；不读取运行时环境变量。

### CompileTimeMinimumLevel

- **Derived field**: `compile_time_min_level: LogLevel`。
- **Rule**: `release_mode == true => info`；`release_mode == false => debug`。
- **Lifecycle**: 编译期常量；产物运行时不可改。
- **Scope**: 不提供按模块、按 scope、按 category 的额外编译期矩阵。

### RuntimeMinimumLevel

- **Field**: `Logger.level`（现有）；`Logger.init(level)` 设置；默认不低于 `compile_time_min_level`。
- **Rule**: `effective_min_level = max(compile_time_min_level, runtime_min_level)`。
- **Compatibility**: 现有 `Logger.init(.info)` 行为不变；现有 `Logger.init(.debug)` 在非 release 可打印 debug，在 release 被编译期下限收敛为 info。

### LogMessage

- **Fields**: `level: LogLevel`, `module: []const u8`, `formatted_text`, `stderr`。
- **Format**: `[LEVEL] module: message\n`；destination stderr；no structured/JSON output。
- **Filtered debug**: no output; no formatting; no extra runtime work; no caller side effects（调用点 pure/guarded）。
- **No persistence**: 不写文件、不缓存、不重排、不重复。

### CompileTimeDebugCall

- **Rule**: `.debug` call in release is comptime-disabled；非 release 可输出。
- **Guard**: 若参数有副作用/成本，调用点必须 `if (Logger.enabledComptime(.debug))` 或 `comptime` guard；不改变现有 info/warn/error call sites。
- **Rejected**: runtime re-enable debug in release；raw unfiltered `print` path in release。

## State transitions

```text
BuildMode(debug)  -> compile_time_min_level=debug
BuildMode(release)-> compile_time_min_level=info

Logger.init(runtime) -> runtime_min_level=runtime
effective_min_level = max(compile_time_min_level, runtime_min_level)
message.level >= effective_min_level -> emit stderr
message.level <  effective_min_level -> drop (comptime-dropped when known)
```

## Validation rules mapped to requirements

- FR-001/FR-002/FR-003: `compile_time_min_level`.
- FR-004: no runtime re-open of debug in release; no env/runtime compile toggle.
- FR-005: comptime drop no output/no formatting/no extra work; caller pure/guard.
- FR-006: retain levels/order.
- FR-007: retain stderr + `[LEVEL] module: message`.
- FR-008: runtime raises threshold only.
- FR-009: no unfiltered raw output in release below info.
- FR-010/FR-011: no change to existing info/warn/error output or build modes.

## Out of scope

- persistent log files, metrics, tracing, JSON logs, scope-level config, runtime env config, new dependencies, toolchain upgrade.

## Field-level constraints (canonical citations)

Cite these as `data-model.md` + `Entity.field`. A task implementing a field must not contradict its canonical definition.

- `LogLevel.debug`: ordering position 0; non-release output allowed; release `.debug` comptime-disabled; prints `[DEBUG]`.
- `LogLevel.info`: ordering position 1; release minimum; prints `[INFO]`.
- `LogLevel.warn`: ordering position 2; prints `[WARN]`.
- `LogLevel.error_`: ordering position 3; prints `[ERROR]`.
- `LogLevel.ordering`: `debug < info < warn < error_`; `level >= effective_min_level` emits.
- `LogLevel.canonical_names`: `debug/info/warn/error_` tags; `[DEBUG]/[INFO]/[WARN]/[ERROR]` text.
- `LogLevel.validation`: release `effective_min_level >= info`; non-release `effective_min_level >= debug`.
- `BuildMode.mode`: `debug` vs `release`.
- `BuildMode.release_mode`: `@import("builtin").mode != .debug`.
- `BuildMode.source`: Zig build selection; `--release`, `--release=fast/safe/small`, `-Doptimize=ReleaseSafe/ReleaseFast/ReleaseSmall`, default Debug.
- `BuildMode.output`: `release_mode`; `compile_time_min_level`.
- `BuildMode.validation`: no runtime env; no release submode distinction.
- `CompileTimeMinimumLevel.compile_time_min_level`: `release_mode == true => info`; `release_mode == false => debug`.
- `CompileTimeMinimumLevel.release_mode`: boolean derived at compile time.
- `CompileTimeMinimumLevel.lifecycle`: comptime constant; cannot change at runtime.
- `CompileTimeMinimumLevel.scope`: global; no per-module/per-scope matrix.
- `RuntimeMinimumLevel.level`: `Logger.level`; `Logger.init(level)`; not lower than compile-time floor.
- `RuntimeMinimumLevel.effective_min_level`: `max(compile_time_min_level, runtime_min_level)`.
- `RuntimeMinimumLevel.rule`: runtime can raise threshold only; release cannot reopen debug.
- `RuntimeMinimumLevel.compatibility`: existing `Logger.init(.info)` unchanged; `Logger.init(.debug)` release converges to `.info`.
- `LogMessage.level`: `LogLevel`.
- `LogMessage.module`: `[]const u8`.
- `LogMessage.formatted_text`: `[LEVEL] module: message\n`.
- `LogMessage.stderr`: destination stderr.
- `LogMessage.format`: `[LEVEL] module: message\n`; no JSON.
- `LogMessage.filtered_debug`: no output/no formatting/no extra work; no caller side effects (pure/guarded).
- `LogMessage.no_persistence`: no files/cache/reordering/duplication.
- `CompileTimeDebugCall.rule`: `.debug` comptime-disabled in release; allowed non-release.
- `CompileTimeDebugCall.guard`: `Logger.enabledComptime(.debug)` / `comptime` guard for side-effect/expensive args.
- `CompileTimeDebugCall.rejected`: runtime reopen in release; raw unfiltered print.
