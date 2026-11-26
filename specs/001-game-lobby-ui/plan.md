# Implementation Plan: 游戏大厅界面

**Branch**: `001-game-lobby-ui` | **Date**: 2026-11-26 | **Spec**: [spec.md](spec.md)

**Input**: 用户显式指定 `specs/001-game-lobby-ui`；当前 git 分支为 `002-upgrade-direct-deps`，本命令按用户指定目录生成计划。

## Summary

在现有 Zig + SDL3 训练场启动时新增一层中文游戏大厅：默认构建先显示大厅，用户一次选择进入默认训练场 / 外部模型预览 / 2D 输入演示 / Vulkan 清屏四模式之一，模式内按 Esc 返回大厅并释放资源；大厅内 Esc 不退出，退出仅由「退出」按钮或关闭窗口触发。两项会话设置（视角灵敏度 0.5–2.0 默认 1.0、音量 0–100 默认 100）在大厅调整、会话内生效、不持久化。方案是在 `main.zig` 顶层循环外包一个轻量 `LobbySession` 状态机，复用 `DemoScene.init/deinit` 与各模式既有绘制路径，不新增依赖、不改变玩法、不破坏 2D/清屏的独立构建门禁。

## Technical Context

**Language/Version**: Zig 0.17.1（精确锁定，`build.zig` 以 `@compileError` 校验，不得变更）；少量 C/C++ 桥接（Jolt、ImGui、miniaudio、cgltf/stb）

**Primary Dependencies**: SDL 3.4.20（经 `fred29910/sdl3-zig` 提交 `aaa5868` 绑定）、Dear ImGui v1.93.0、Jolt Physics v5.7.0、cgltf v1.15、stb `6b5799b`、miniaudio 0.11.26；**本功能不新增外部依赖**（若需中文字体，使用随仓库提供的 TTF 资源，见 `research.md` R5）

**Storage**: 无持久化存储；会话设置仅存在于进程内，重启恢复默认；GLB 与 SPIR-V 仍嵌入可执行文件

**Testing**: G1 `zig build install test`、G2 `zig build install test -Doptimize=ReleaseSafe`、G3 `zig build physics-test`、G4 `zig build test -Ddemo-2d=true`、G5 `zig build test -Dclear-only=true`；端到端场景 V1–V6 见 [quickstart.md](quickstart.md)，判定见 [contracts/acceptance-gates.md](contracts/acceptance-gates.md)

**Target Platform**: Linux 桌面为验收基线（Xvfb + Mesa Lavapipe 软件 Vulkan）；无桌面冒烟可用 `SDL_VIDEODRIVER=offscreen` / `dummy` + software renderer

**Project Type**: 桌面第一人称训练场 Demo（Zig 主导 + C/C++ 桥接）

**Performance Goals**: 启动到开始操作训练场 ≤2 次明确选择且 <3 秒（SC-001）；保持 M11 已记录的帧率基线，无可观测回退

**Constraints**: Zig 版本与依赖哈希精确锁定；不得引入浮动版本；`-Ddemo-2d=true` 与 `-Dclear-only=true` 必须保持独立构建/测试，不依赖 Jolt、资产导入、ImGui、音频；可见文本全部中文且与 README 术语一致；不改变 glTF 支持边界、物理/相机不变量（1/60s、每帧最多 6 步、相机 1.6m、最近碰撞射线）与缓存语义（`缓存命中 embedded:demo.glb`）；HLSL/SPIR-V 保持同步；不修改生成物与缓存目录

**Scale/Scope**: 1 个大厅 + 4 个既有模式 + 2 项会话设置；本地单用户，无联网、账号、匹配或多人房间；无第五种模式

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| 原则/门禁 | 判定 | 依据 |
| --- | --- | --- |
| I. 精确版本与锁定依赖 | PASS | 不新增/升级依赖；若引入中文字体则作为 `assets/` 资源纳入，不改 `build.zig.zon` 版本与哈希 |
| II. 测试先行与验收门禁（NON-NEGOTIABLE） | PASS | 先写 G1–G5 与 V1–V6 的可执行验证步骤（`quickstart.md`、`contracts/acceptance-gates.md`），再实现；任何失败即修复重跑，不放宽门禁 |
| III. 增量改动与零回归 | PASS | 复用 `DemoScene.init/deinit` 与既有绘制路径；只在大厅入口/退出路径改变行为；玩法、验收记录、资产与物理代码不变 |
| IV. 资源生命周期与确定性状态 | PASS | 返回大厅时按模式调用对应 `deinit`；重进模式不残留状态；设置会话内生效、不持久化，不引入全局隐式状态 |
| V. 简洁克制与边界清晰 | PASS | YAGNI：仅四大模式与两项设置；不新增模式、网络能力或持久化；源码改动限于必要参数接口 |
| 图形/物理/着色器不变量 | PASS | 不动 HLSL/SPIR-V、物理步长/相机高度/射线规则与缓存语义；灵敏度只替换硬编码系数，默认值保持等效 0.0025 rad/px |

**结论**：无违规，无需 Complexity Tracking。

**Phase 1 设计后复核**：PASS — 设计产物（`research.md`、`data-model.md`、`contracts/`、`quickstart.md`）未引入工具链变更、依赖变更或不变量改动；`build.zig:53` 的 2D/清屏守护保持不变（见 research.md R1/R6）。R5 字体决策为随仓库内置中文字体资源（不新增外部依赖、离线可复现），符合宪章 I/V。

## Project Structure

### Documentation (this feature)

```text
specs/001-game-lobby-ui/
├── plan.md                      # 本文件
├── spec.md                      # 已澄清特性规格
├── research.md                  # Phase 0：现状 recon 与六项决策
├── data-model.md                # Phase 1：实体、字段、校验与状态流转
├── quickstart.md                # Phase 1：端到端验证指南
├── contracts/
│   ├── acceptance-gates.md      # Phase 1：门禁与判定规则
│   └── lobby-ui.md              # Phase 1：大厅 UI 契约（文案/控件/状态）
├── ui-design.md                 # Phase 1：designer 完整 UI/UX 设计（断点/文案/D-01–D-18）
├── checklists/requirements.md   # 规格质量清单（既有）
└── tasks.md                     # 由 /speckit.tasks 生成，本命令不创建
```

### Source Code (repository root)

```text
src/main.zig                         # 顶层循环：大厅路由、Esc 分派、模式进入/退出
src/engine/gameplay/lobby.zig        # 新增：LobbySession 状态机与设置值持有
src/engine/renderer/imgui_bridge.cpp # 新增大厅绘制入口 + 中文字体加载（不动既有 HUD/Init/Shutdown）
src/engine/renderer/camera.zig       # Camera.sensitivity 参数（默认等效 0.0025）
src/engine/audio/demo_audio.zig      # 新增 demo_audio_set_volume 包装
src/engine/audio/miniaudio_bridge.c  # 音量应用（0–100 → 0.0–1.0）
assets/                              # 中文字体资源（如需要，随构建路径纳入）
build.zig                           # 仅当新增字体资源需纳入 paths 时微调；守护分支不变
README.md                            # 同步操作表（Esc 语义）与验收清单
shaders/                             # 不变（HLSL 与 SPIR-V 保持同步）
zig-pkg/ zig-out/ .zig-cache/        # 生成物与缓存，禁止手工编辑
```

**Structure Decision**: 单项目仓库，新增一个 `src/engine/gameplay/lobby.zig` 作为大厅状态机；其余改动是对既有入口、ImGui、相机、音频与文档的小幅增量扩展。不新增构建目标，不新增外部依赖。

## Complexity Tracking

> 无 Constitution Check 违规，本节不适用。
