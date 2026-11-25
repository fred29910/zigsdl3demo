# Implementation Plan: 升级直接依赖至最新版本

**Branch**: `002-upgrade-direct-deps` | **Date**: 2026-11-25 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/002-upgrade-direct-deps/spec.md`

## Summary

盘点 `build.zig.zon` 中声明的 6 项直接依赖，逐项检查上游最新版本并判定与锁定的 Zig 0.17.1 工具链及既有验收门禁的兼容性。对兼容者以精确版本/提交与固定哈希升级；对无兼容更新者保持原样并记录理由。升级完成后全部既有门禁通过、干净环境可离线构建，并在 README 留下「原版本 → 新版本/保持原样 + 理由」的可追溯记录。工具链版本、已验收的玩法与不变量均不改变。

## Technical Context

**Language/Version**: Zig 0.17.1（精确锁定，`build.zig` 以 `@compileError` 校验，不得变更）

**Primary Dependencies**: SDL 3.4.20（经 `fred29910/sdl3-zig` 提交 `aaa5868` 绑定）、Jolt Physics v5.5.0、Dear ImGui v1.92.5、cgltf v1.15、stb 提交 `f0569113`、miniaudio 0.11.26；Tracy v0.12.2 为可选外部源码（经 `-Dtracy-source` 启用，不在依赖清单中）

**Storage**: 无持久化存储；GLB 与 SPIR-V 嵌入可执行文件，外部资源按相对路径读取

**Testing**: `zig build install test`、`zig build install test -Doptimize=ReleaseSafe`、`zig build physics-test`、`zig build test -Ddemo-2d=true`、`zig build test -Dclear-only=true`；另需干净环境离线构建验证

**Target Platform**: Linux 桌面为验收基线（Xvfb + Mesa Lavapipe 软件 Vulkan）；Windows/macOS 由依赖支持但不在本功能验证范围

**Project Type**: 桌面游戏 Demo（Zig 主导，含 C/C++ 桥接：Jolt、ImGui、miniaudio、cgltf/stb）

**Performance Goals**: 保持 M11 已记录的帧率基线，升级后不得引入可观测的性能回退

**Constraints**: Zig 版本与全部依赖哈希精确锁定；不得引入浮动版本；升级后必须离线干净构建；不得改变 glTF 支持边界、物理与相机不变量（1/60s 步长、每帧最多 6 步、相机 1.6m、最近碰撞射线）与缓存语义；文档语言为中文

**Scale/Scope**: 6 项直接依赖，其中 3 项存在上游更新（Jolt、ImGui、stb），3 项已是最新（cgltf、miniaudio、sdl3-zig/SDL）

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| 原则/门禁 | 判定 | 依据 |
| --- | --- | --- |
| I. 精确版本与锁定依赖 | PASS | 升级以精确 tag/提交 + `zig fetch` 哈希落地；不引入浮动引用；Zig 0.17.1 不变 |
| II. 测试先行与验收门禁（NON-NEGOTIABLE） | PASS | RED：T011 先写目标版本检查脚本，T012 运行确认失败并取得用户确认后才进入 GREEN；GREEN：逐项升级后以既有门禁 G1–G6 验证，失败即回退。见 `tasks.md` 与 `contracts/acceptance-gates.md` |
| III. 增量改动与零回归 | PASS | 逐项升级、逐项验证；失败回退到最后通过门禁的版本；不修改生成物目录 |
| IV. 资源生命周期与确定性状态 | PASS | 不触及场景资源生命周期、缓存语义与物理/相机不变量 |
| V. 简洁克制与边界清晰 | PASS | 仅版本与哈希变更，不新增功能、不改变支持边界 |
| 图形/物理/着色器不变量 | PASS | 不改 HLSL/SPIR-V；Jolt 升级若破坏 1/60s 步长等不变量则回退 |

**结论**：无违规，无需 Complexity Tracking。

**Phase 1 设计后复核**：PASS — 设计产物未引入工具链变更、浮动引用或不变量改动；候选升级均以门禁判定与逐项回退为边界，`zig fetch` 命令已按 Zig 0.17.1 实际接口校正；已补充显式 RED-GREEN 任务序列（T011/T012 → T013–T019），满足宪章 II。

## Project Structure

### Documentation (this feature)

```text
specs/002-upgrade-direct-deps/
├── plan.md              # 本文件
├── research.md          # Phase 0：上游版本调研与兼容性决策
├── data-model.md        # Phase 1：实体、字段、校验与状态流转
├── quickstart.md        # Phase 1：可运行的验证步骤
├── contracts/
│   ├── dependency-manifest.md   # Phase 1：依赖声明契约
│   └── acceptance-gates.md      # Phase 1：验收门禁契约
└── tasks.md             # 由 /speckit.tasks 生成，本命令不创建
```

### Source Code (repository root)

```text
build.zig.zon            # 直接依赖声明：本功能唯一需要改写的依赖源文件
build.zig                # 构建图与测试步骤；仅验证兼容性，不改构建逻辑
README.md                # 依赖表与升级记录（SC-006 留痕位置）
src/                     # 原则上不改；仅当门禁因依赖 API 变化失败时允许 FR-011 的最小源码适配，否则作为回退判定依据
docs/                    # 如需补充验收记录则在此更新
zig-pkg/ zig-out/ .zig-cache/   # 生成物与缓存，禁止手工编辑
```

**Structure Decision**: 单项目仓库，无新增源码目录。改动集中在 `build.zig.zon` 与文档；门禁命令沿用现有构建步骤，不新增构建目标。

## Complexity Tracking

> 无 Constitution Check 违规，本节不适用。
