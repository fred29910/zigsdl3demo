# Implementation Plan: 训练模式操控完善

**Branch**: `004-training-mode-controls` | **Date**: 2026-11-26 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/004-training-mode-controls/spec.md`

## Summary

现有训练场已经具备鼠标转视角、WASD 移动、冲刺、跳跃、沿墙滑动、灵敏度设置与失焦暂停。本次不是新增系统，而是把这些行为按规格固化：用自动化测试锁定视角映射与俯仰限幅、移动方向解释与斜向限速、单次起跳、失焦/暂停/重开时输入状态清理，并补齐 README 操作与验收记录。

技术路径是复用并收紧现有代码路径：`InputState`（按键边沿、鼠标增量、失焦清理）→ `Camera.look`（偏航/俯仰、灵敏度）与 `World.setCharacterInput`（瞬时速度、归一化、跳跃 pending）→ `DemoScene.updateTraining`（捕获时才转视角、暂停时 `setCharacterInput(null)`、重开重置相机）。不引入加速/减速过渡（已澄清为瞬间启停），不新增设置开关，不改变物理步长、眼高与碰撞规则，不改变构建图。

## Technical Context

**Language/Version**: Zig 0.17.1（`build.zig` 顶部 `@compileError` 精确校验）；少量 C/C++ 桥接由 Zig 直接编译。

**Primary Dependencies**: sdl3-zig（SDL 3.4.20，提交 `aaa5868`）用于窗口/输入/SDL GPU；Jolt Physics v5.7.0 用于角色与碰撞；Dear ImGui v1.93.0 用于大厅设置与 HUD；miniaudio 0.11.26 用于训练场音效。本功能只涉及 SDL 输入、Jolt 角色驱动、ImGui 设置回传，不新增依赖。

**Storage**: N/A。设置仅存在于会话内存（`lobby.Settings`），不持久化；无数据库或文件存储。

**Testing**: Zig 内置单元测试，命令为 `zig build install test`；无窗口物理/角色测试 `zig build physics-test`；基础模式独立测试 `zig build test -Ddemo-2d=true` 与 `zig build test -Dclear-only=true`；发布安全复测 `zig build install test -Doptimize=ReleaseSafe`。验收基线为 Linux 虚拟显示（Xvfb）+ Mesa Lavapipe 软件 Vulkan。

**Target Platform**: Linux 桌面应用；验收基线为虚拟显示 + 软件 Vulkan。真实 GPU 桌面窗口管理器与物理播放设备不在已验证范围。

**Project Type**: 桌面 GUI 应用——SDL3 GPU 第一人称训练场 Demo，含中文游戏大厅、默认训练场、外部模型查看、2D 输入演示与清屏演示。

**Performance Goals**: 60 FPS 交互基线；物理固定步长 1/60 秒、每帧最多 6 步；视角与移动输入在当前帧生效，不引入超过一个物理步的额外延迟；瞬间启停（FR-014）不增加缓动计算。

**Constraints**: Zig 版本与 `build.zig.zon` 哈希锁定；提交 SPIR-V 与 HLSL 同步且不改动；物理不变量（1/60 步长、6 步上限、眼高 1.6m、射线取最近碰撞）保持不变；`-Ddemo-2d=true` 与 `-Dclear-only=true` 必须能独立构建与测试；文档语言为中文，标识符/命令/路径保持英文。

**Scale/Scope**: 单玩家本地 Demo；一个内嵌训练场、一个靶板、一个机器人；会话级设置；无网络、无存档、无多用户。

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| 原则 / 门禁 | 结论 | 依据与本计划中的落实 |
| --- | --- | --- |
| I. 精确版本与锁定依赖 | 通过 | 不升级 Zig，不新增依赖，不改 `build.zig.zon`；仅使用已锁定的 SDL/Jolt/ImGui。 |
| II. 测试先行与验收门禁（NON-NEGOTIABLE） | 通过 | 先补测试使其覆盖 FR/SC，再修正行为差异；实施阶段必须依次运行 `zig build install test`、`zig build physics-test`、两种模式测试及 ReleaseSafe 复测。 |
| III. 增量改动与零回归 | 通过 | 改动限于 `input.zig`、`camera.zig`、`world.zig`、`demo_scene.zig`、`physics_test.zig` 与 README；先定位符号再编辑；不碰生成物与缓存目录。 |
| IV. 资源生命周期与确定性状态 | 通过 | 保留重开时“先建新世界再释放旧世界”的顺序；改用 `Camera.resetForRound()` 重置视角与位置但保留会话灵敏度；暂停/失焦/回合结束/重开时清理按住状态，暂停时仍调用 `setCharacterInput(null)`；保留缓存语义。 |
| V. 简洁克制与边界清晰 | 通过 | 不新增 Y 轴反转、垂直灵敏度、蹲伏等开关；范围限定于视角与移动操控；README 明确支持范围。 |
| 图形、物理与着色器不变量 | 通过 | 不改 HLSL/SPIR-V、光照与阴影参数；不改物理步长、步数上限、眼高与射线规则；瞬间启停保持现有速度模型。 |
| 开发工作流与质量门禁 | 通过 | 使用 Spec Kit 流程；新增/修改功能同步 README 操作表、架构表与验收记录；提交信息沿用 `feat:` / `docs:` 前缀与中文描述。 |

设计后复核：Phase 0/1 产出未引入新依赖、新设置、新物理参数或构建图变更；上述门禁仍全部通过，无需 Complexity Tracking 例外。

## Project Structure

### Documentation (this feature)

```text
specs/004-training-mode-controls/
├── plan.md              # 本文件（/speckit.plan 输出）
├── research.md          # Phase 0 输出（/speckit.plan）
├── data-model.md        # Phase 1 输出（/speckit.plan）
├── quickstart.md        # Phase 1 输出（/speckit.plan）
├── contracts/           # Phase 1 输出（/speckit.plan）
│   └── input-controls.md
└── tasks.md             # Phase 2 输出（/speckit.tasks，本命令不创建）
```

### Source Code (repository root)

```text
src/
├── main.zig                              # 事件循环、Tab 捕获、失焦释放、设置应用入口
├── engine/
│   ├── platform/sdl/input.zig            # Action 映射、InputState 边沿与鼠标增量、setMouseCaptured
│   ├── renderer/camera.zig               # 视角 yaw/pitch、灵敏度映射、look()
│   ├── renderer/demo_scene.zig           # updateTraining 输入分发、暂停取消输入、重开重置
│   ├── physics/world.zig                 # CharacterInput、setCharacterInput 归一化与瞬时速度
│   └── gameplay/lobby.zig                # Settings 灵敏度/音量与钳制
└── physics_test.zig                      # 无窗口角色移动、冲刺、沿墙、跳跃边沿测试
README.md                                 # 操作表与「测试与验收」记录（需同步）
```

**Structure Decision**: 单项目增量改动，沿用现有 `src/engine/...` 分层，不新增顶层源码目录。`camera.fly` 属于外部模型自由飞行模式，训练场移动继续由 Jolt 角色驱动，两者不合并。仅新增本特性目录下的设计文档与 `contracts/` 契约文档。

## Complexity Tracking

Constitution Check 无违规，本节不需要记录例外。
