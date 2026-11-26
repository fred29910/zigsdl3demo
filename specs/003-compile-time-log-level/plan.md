# Implementation Plan: 优化日志系统并支持编译期发布模式过滤 debug 日志

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal**: 让当前自定义日志系统在**编译期**按发布模式过滤：`zig build --release` 产物仅输出 info 及以上；非发布构建允许输出 debug；不改变现有 info/warn/error 输出、格式、目的地与构建模式。

**Architecture**: 保留 `src/engine/core/logger.zig` 的 `Logger`，不迁移 `std.log`。用 `@import("builtin").mode != .debug` 得到 `release_mode`；`compile_time_min_level = release ? .info : .debug`；`effective_min_level = max(compile_time_min_level, runtime_level)`；`.debug` 在 release 下 comptime 丢弃；保留 stderr `[LEVEL] module: message`；关闭未过滤 `print` 绕过。`build.zig` 在保留 `-Doptimize=...` 的同时，让 Zig 0.17.1 裸 `zig build --release` 获得非 Debug。

**Tech Stack**: Zig `0.17.1`；现有 `std`；现有 SDL3/Jolt 等依赖不变；不新增依赖；不改 shader；不改生成物。

**Spec**: [spec.md](spec.md)

## Global Constraints

- Zig 必须精确 `0.17.1`；保留 `@compileError`；不升级工具链。
- 不修改 `build.zig.zon`；不使用浮动版本或覆盖依赖哈希；首次构建可联网，之后可离线。
- 不修改 `zig-pkg/`、`zig-out/`、`.zig-cache/`；不手工改 `.opencode/commands/`、`.specify/templates/`、`.specify/scripts/`。
- `.spv` / `.hlsl` 无变更；不影响 shader 构建。
- 不破坏 `-Ddemo-2d=true` 与 `-Dclear-only=true`；这两种模式跳过 Jolt/资产/ImGui/音频，不得新增依赖。
- 任意改动至少 `zig build install test`；发布与非发布都要测试；两种基础模式独立构建/测试。
- 本特性无物理/碰撞/角色/武器改动，不要求 `zig build physics-test`；若实现触及这些区域，必须补跑。
- 不破坏已验收行为；物理 1/60s、每帧最多 6 步、1.6m 相机、最近碰撞等不变量不变。
- 资源生命周期不变；无新增持久资源。
- 文档中文；标识符/命令/路径英文；新增注释中文；提交 `feat:` + 中文。
- 实现阶段同步 README 对应构建/日志/测试/验收；原子提交。
- 功能范围 YAGNI：不新增运行时 env/flag；不新增 per-module/per-scope 编译矩阵；不新增 JSON/结构化日志；不改输出格式。
- **debug 级别调用点**：当前无；新增 `.debug` 必须无副作用；昂贵/可能有副作用参数必须 `if (Logger.enabledComptime(.debug))` 或 `comptime` guard。
- release 不能重新打开 debug；不新增 `std_options` 运行时切换；不改 `std.log`。
- release 下 `effective_min_level >= .info`；非 release `effective_min_level >= .debug`；`effective_min_level = max(compile_time_min_level, runtime_level)`。
- release 输出 info + warn + error_；非 release 输出 debug + info + warn + error_；级别顺序 `debug < info < warn < error_`；文本 `[DEBUG]/[INFO]/[WARN]/[ERROR]`；stderr。

## Review Focus

1. **裸 `zig build --release` on Zig 0.17.1**: 当前 `standardOptimizeOption(.{})` 会 `.any => exit(1)`；实现必须不破坏 `-Doptimize=ReleaseSafe`。验证 `zig build install test --release`。
2. **`-Doptimize` 与 `--release` 同时出现**: `-Doptimize=ReleaseSafe/ReleaseFast/ReleaseSmall` 仍可用，且不能被 `--release` 静默丢弃；任何非 Debug 都 info+。
3. **过滤日志参数求值**: `log.log(.debug, ..., expr)` 不能让 `expr` 产生副作用/开销；Zig 无任意参数惰性求值宏；需 comptime guard 测试。
4. **未过滤输出绕过**: 当前 `Logger.print` 不受过滤且未使用；release 下不得保留低于 info 的 raw output；`Logger.log` 内 `std.debug.print` 只能在已放行分支。
5. **两种基础演示模式**: `-Ddemo-2d=true` / `-Dclear-only=true` 在 release 与非 release 都可独立构建/测试；不得引入 Jolt/assets/ImGui/audio。
6. **既有输出回归**: 现有 `.info/.warn/.error_` 输出、`[LEVEL] module: message\n`、stderr、module、运行时 `Logger.init(.info)` 不变；字节级对比。

## Summary

从 `spec.md` 提取：**优化当前日志系统；增加编译期发布过滤；`--release` → 仅 info+；非 `--release` → debug 可打印；不回归。** 技术路线见 Phase 0 [research.md](research.md)：保留自定义 `Logger`；comptime 最低级别；runtime 只能收紧；`build.zig` 保留 `-Doptimize` 并支持裸 `--release`；禁用未过滤 `print`；不新增依赖。

## Technical Context

<!-- Preserved template fields; no unknowns remain after Phase 0. -->

**Language/Version**: Zig `0.17.1`（不放宽版本检查）

**Primary Dependencies**: 现有 `std`；现有 `sdl3` / Jolt / cgltf / stb / miniaudio / ImGui 等锁定依赖不变；**无新增依赖**

**Storage**: N/A；不持久化日志；输出 stderr

**Testing**: `zig build install test`；`zig build install test --release`；`zig test src/engine/core/logger.zig`；`zig build test -Ddemo-2d=true`；`zig build test -Dclear-only=true`；release 对应命令；无窗口 smoke 见 README

**Target Platform**: Linux x86_64 验收基线（Mesa Lavapipe + SDL offscreen/dummy）；不扩大平台承诺

**Project Type**: single-project Zig library + executable

**Performance Goals**: filtered `.debug` 无输出/无格式化/无额外运行时开销；info/warn/error 热路径不回归；无新增分配

**Constraints**: no toolchain upgrade；no dependency change；no runtime logging env；no output format change；no generated-file edits；no shader change；Debug vs release only difference is `.debug` emission

**Scale/Scope**: 单仓库；现有 70+ `.log` 调用点；当前无 `.debug`；两种基础演示模式；无外部服务

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Before Phase 0

- **I. 精确版本与锁定依赖**: PASS。Zig 0.17.1；不改 `build.zig.zon`；不改生成物；不破坏离线构建。
- **II. 测试先行与验收门禁 (NON-NEGOTIABLE)**: PASS（计划层面）。实现阶段 Red-Green-Refactor；先写失败测试并获确认；`zig build install test`；release 复测；两种基础模式可独立构建/测试。本阶段未宣称已跑全量测试。
- **III. 增量改动与零回归**: PASS。只改日志核心、最小 build 选择、测试、README；不破坏 M0–M11；不手改生成物；Linux Lavapipe 基线。
- **IV. 资源生命周期与确定性状态**: PASS。无新增资源；日志只读输出；不改缓存/Jolt/物理参数。
- **V. 简洁克制与边界清晰**: PASS。YAGNI；不新增格式/输出/scope/runtime 开关；明确不做。

### After Phase 1 design

- **I. 精确版本与锁定依赖**: PASS。`data-model.md` / contract 不升级 Zig、不加依赖。
- **II. 测试先行与验收门禁**: PASS。`quickstart.md` 给出验证命令与期望；focused checks 明确。
- **III. 增量改动与零回归**: PASS。输出与调用点兼容；两种基础模式保留。
- **IV. 资源生命周期与确定性状态**: PASS。无资源变化。
- **V. 简洁克制与边界清晰**: PASS。不引入额外子系统。

**No violations.** `## Complexity Tracking` 无需填写。

### Known finding requiring implementation action

裸 `zig build --release` 在 **当前未改代码** Zig 0.17.1 + `standardOptimizeOption(.{})` 下实测失败。这不是放宽约束；本计划要求 `build.zig` 让 `--release` 正常产生非 Debug，同时保留 `-Doptimize=...`。

## Project Structure

### Documentation (this feature)

```text
specs/003-compile-time-log-level/
├── plan.md              # 本文件（/speckit.plan 输出）
├── research.md          # Phase 0
├── data-model.md        # Phase 1
├── contracts/
│   └── logging-contract.md  # Phase 1 外部契约
├── quickstart.md        # Phase 1 验证
└── tasks.md             # Phase 2 /speckit.tasks 输出，本命令不创建
```

### Source Code (repository root)

```text
src/
├── root.zig                         # 暴露 Logger；不新增 runtime 开关
├── main.zig                         # 现有调用点不改语义
├── engine/
│   ├── core/
│   │   └── logger.zig               # compile-time floor + runtime clamp + tests
│   ├── assets/                      # 现有 info/warn/error 不改
│   └── renderer/                    # 现有 info/warn/error 不改
build.zig                            # 仅调整 optimize/release 选择；不动 shader/依赖
README.md                            # 构建/日志/验收文档同步
```

**Structure Decision**: 单项目；保持现有 `src/engine/core/logger.zig` 边界；不拆新 logging 子系统；不改 assets/renderer/physics 输出。

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

无违反；无需填写。

## Phase 0: Outline & Research

完成。见 [research.md](research.md)。无 `NEEDS CLARIFICATION`。

- Decision / Rationale / Alternatives considered 已记录。
- 未引入外部服务、数据库、网络、新依赖。
- 对 `std.log` 仅作为替代方案对照；**不迁移**。
- 记录 Zig 0.17.1 裸 `--release` 实测问题与 `-Doptimize` 兼容。
- 记录 Zig 参数求值限制与 FR-005 guard。

## Phase 1: Design & Contracts

完成。见 [data-model.md](data-model.md)、[contracts/logging-contract.md](contracts/logging-contract.md)、[quickstart.md](quickstart.md)。

### Concrete design

- `src/engine/core/logger.zig`：
  - `pub const release_mode = @import("builtin").mode != .debug;`
  - `pub const compile_time_min_level: Level = if (release_mode) .info else .debug;`
  - `Logger.level` runtime；`effectiveMinLevel()` / `enabledComptime(level)`；`enabled(level)` clamp；`log` `comptime level` + `if (comptime !enabledComptime(level)) return;`
  - 保留 `Level`, `levelName`, `init`, `format`, `log`, `print` replacement semantics；现有 output 不变。
  - 删除/禁用未过滤 `Logger.print`；无 release raw output below info。
- `src/root.zig`：`pub const Logger` 不变；可 re-export `compile_time_min_level` / `release_mode`。
- `build.zig`：
  - preserve `-Doptimize=...`；
  - support bare `--release` on Zig 0.17.1 without breaking `-Doptimize=ReleaseSafe`；precedence: explicit `-Doptimize=...` > `--release=<mode>` > bare `--release` => `.ReleaseSafe` > `.Debug`；
  - no `-Dlog-level`; no logging env; no shader/dependency changes.
- tests in `src/engine/core/logger.zig` first (TDD later).

### Contracts

- External/user-facing contract: [contracts/logging-contract.md](contracts/logging-contract.md).
- No network API, no file format, no generated artifact contract; only build + logging semantics.

### Quickstart

[quickstart.md](quickstart.md) lists runnable non-release/release/basic-mode/focused checks and expected outcomes.

## Next

- `/speckit.tasks` generates `tasks.md`; not created by `/speckit.plan`.
- Implementation must use TDD and verify `/speckit.converge` readiness per constitution.
