# Contract: Logging system compile-time minimum level

**Feature**: `003-compile-time-log-level`
**Date**: 2026-11-26
**Audience**: builders and Zig call sites; no network/wire contract.

## Build contract

- **Release**: `zig build --release` MUST select a non-Debug optimization for this project; also `zig build --release=fast`, `--release=safe`, `--release=small`, `-Doptimize=ReleaseSafe`, `-Doptimize=ReleaseFast`, `-Doptimize=ReleaseSmall`.
- **Precedence**: explicit `-Doptimize=...` wins; otherwise `--release=<mode>` maps to that mode; otherwise bare `--release` maps to `.ReleaseSafe`; otherwise Debug. This preserves existing `-Doptimize` behavior and gives bare `--release` a deterministic non-Debug mode on Zig 0.17.1.
- **Non-release**: default `zig build`, `zig build test`, `-Doptimize=Debug`, `-Doptimize=debug` remain Debug.
- **No new required flag**: caller does not need `-Dlog-level`, env var, runtime arg, or config file.
- **No regression**: `-Doptimize=ReleaseSafe` continues to work; `-Ddemo-2d=true` and `-Dclear-only=true` remain independently buildable/testable; Zig remains `0.17.1`; no dependency change.

## Effective level contract

```text
release_mode = @import("builtin").mode != .debug
compile_time_min_level = if (release_mode) .info else .debug
effective_min_level = max(compile_time_min_level, Logger.level)
```

- `Logger.Level` remains `debug/info/warn/error_`.
- `info+` = `info`, `warn`, `error_`.
- release (`release_mode=true`): **only info+**; `.debug` comptime-disabled; runtime cannot lower below `.info`.
- non-release: `.debug` **can** be emitted; runtime can raise minimum; cannot lower below `.debug`.
- ordering: `debug < info < warn < error_`.
- `Logger.init(level)` remains; `Logger.enabled(level)` returns `level >= effective_min_level`.
- `Logger.enabledComptime(level)` exposes compile-time check for guarding expensive/side-effecting args; **no debug call in release emits**.

## Output contract

- destination: `stderr`.
- text format: `[LEVEL] module: message\n`.
- levels rendered `[DEBUG]`, `[INFO]`, `[WARN]`, `[ERROR]`.
- existing `info/warn/error_` call sites unchanged and output-identical.
- no structured/JSON output; no new output sink.
- **No unfiltered raw output in release**: `Logger.print` unfiltered raw output is removed/disabled; no path emits below info in release. `std.debug.print` inside `Logger.log` only after comptime filtering.
- filtered `.debug`: no output, no formatting, no new sink, no runtime branch requirement when comptime known. Zig evaluates function arguments before entry, so the logger cannot stop caller-side argument evaluation; caller MUST keep args pure or use `enabledComptime(.debug)` guard. This is a caller contract with a dedicated verification task, not an unconditional system guarantee.

## Compatibility contract

- `src/root.zig` continues `pub const Logger = ...`.
- `Logger.format`, `Logger.log`, `Logger.enabled`, `Logger.init`, `Level`, `levelName` remain; `print` removed only if no call sites; no `.debug` existing call sites required.
- `log.log(.error_, ...)`, `.warn`, `.info`, `.debug` forms remain syntactically valid; `.debug` is no-op in release.
- no `std.log` migration in this feature; no `std_options` requirement for this custom logger.

## Verification contract

See [quickstart.md](../quickstart.md). Minimum evidence: unit tests for ordering/format/floor; release vs non-release debug test; no-arg-eval test; no info regression; full `zig build install test` + release + two basic modes.
