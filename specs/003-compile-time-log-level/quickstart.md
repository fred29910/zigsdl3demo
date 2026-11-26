# Quickstart Validation: 编译期发布模式日志过滤

**Feature**: `003-compile-time-log-level`
**Preconditions**: Zig `0.17.1`; repo root; dependencies already vendored/locked; no source edits for validation except the feature implementation itself.

## Reference docs

- Spec: [spec.md](spec.md)
- Research: [research.md](research.md)
- Data model: [data-model.md](data-model.md)
- Contract: [contracts/logging-contract.md](contracts/logging-contract.md)

## Claims to prove

1. **Release `--release` works in this project** and produces non-Debug.
2. **Release only info+**: debug count = 0; info/warn/error unchanged.
3. **Non-release debug can print**: debug count >= 1; info/warn/error unchanged.
4. **Only difference** is debug output; no runtime env/arg needed.
5. **No regression**: full tests both modes; two basic modes both modes; format byte-identical for existing logs.
6. **Filtered debug no overhead/side effects**.

## Commands

### Baseline / unit tests (non-release)

```sh
zig version                         # 0.17.1
zig build install test
```

Expected: exit 0; no debug filtered in Debug; existing logs unchanged.

### Release full tests

```sh
zig build install test --release
```

Expected: exit 0; `zig build --release` no longer reports missing preferred optimization mode; only info+ logging.

### Explicit release modes

```sh
zig build install test --release=safe
zig build install test --release=fast
zig build install test --release=small
zig build install test -Doptimize=ReleaseSafe
```

Expected: exit 0; any non-Debug mode => info+ only.

### Basic demo modes (non-release + release)

```sh
zig build test -Ddemo-2d=true
zig build test -Dclear-only=true
zig build test -Ddemo-2d=true --release
zig build test -Dclear-only=true --release
```

Expected: exit 0; no Jolt/assets/ImGui/audio dependency introduced for these modes.

### Logging-focused focused checks

```sh
zig test src/engine/core/logger.zig
```

Expected: logger unit tests pass in Debug. Run same test binary target under release in implementation validation.

### Smoke runs (optional; no desktop required per README)

Use README offscreen/dummy SDL modes after implementation. Compare stderr logs:

```sh
# non-release capture
zig build run -- ... 2> /tmp/opencode/debug.log

# release capture
zig build run --release -- ... 2> /tmp/opencode/release.log
```

Expected release `/tmp/opencode/release.log` has no `[DEBUG]`; info/warn/error format unchanged; release has no extra debug text.

## Focused implementation checks to add in `/speckit.tasks`

- Unit: `Level` ordering `debug < info < warn < error_`; `levelName`.
- Unit: `format` exact `[INFO] core: hello 42\n`.
- Unit: `compile_time_min_level` debug vs release; `effective_min_level = max(compile, runtime)`.
- Unit: release `.debug` disabled; runtime `.init(.debug)` cannot lower below compile floor.
- Unit: non-release `.debug` emitted; `.init(.info)` can still suppress debug at runtime.
- Unit: `print` removed/disabled; no unfiltered release path.
- Comptime/no-overhead: `.debug` call in release emits no output and no formatting; pure args no extra work; side-effect/expensive args require `enabledComptime` guard.
- Regression: existing info/warn/error output byte-identical before/after; no changes to physics/camera/asset behavior.
- Build: no toolchain/dependency edits; no generated `.spv`, `zig-pkg`, `zig-out`, `.zig-cache` edits.

## Current Phase 1 evidence

Not implementation. This session verified only:
- `zig version` = `0.17.1`.
- `zig build -Doptimize=ReleaseSafe --summary none` exit 0 on unmodified project.
- unmodified `zig build --release --verbose` fails asking `--release=fast/safe/small`.
- source reads: `src/engine/core/logger.zig`, `src/root.zig`, `src/main.zig`, `build.zig`, Zig 0.17.1 `std.Build`, `std.log`, `std.Options`, `std.lang.Optimize`.

## Implementation verification evidence (2026-11-26)

All commands run from repo root; exit status 0 unless stated.

- `zig version` -> `0.17.1`
- `zig test src/engine/core/logger.zig` -> 6/6 pass (Debug)
- `zig test src/engine/core/logger.zig -OReleaseSafe` -> 6/6 pass
- `zig build install test` -> exit 0
- `zig build install test --release` -> exit 0
- `zig build install test -Doptimize=ReleaseSafe` -> exit 0
- `zig build test -Ddemo-2d=true` -> exit 0
- `zig build test -Dclear-only=true` -> exit 0
- `zig build test -Ddemo-2d=true --release` -> exit 0
- `zig build test -Dclear-only=true --release` -> exit 0
- `zig build --release --summary none` -> exit 0 (bare `--release` now supported)
- `zig build --release=fast --summary none` -> exit 0
- `zig build --release=safe --summary none` -> exit 0
- `zig build --release=small --summary none` -> exit 0

Temporary probe (`Logger.init(.debug)` emitting debug/info/warn/error):
- Debug: `[DEBUG]`, `[INFO]`, `[WARN]`, `[ERROR]` all present.
- ReleaseSafe: `[INFO]`, `[WARN]`, `[ERROR]` present; `[DEBUG]` absent.
- Probe file removed; no temporary source left in repo.

Not verified: real desktop GPU window manager, physical audio playback. Validation baseline is Linux virtual display + Mesa Lavapipe as documented.
