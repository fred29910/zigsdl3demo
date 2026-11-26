# Research: 训练模式操控完善

**Feature**: `004-training-mode-controls` | **Date**: 2026-11-26

**Method**: 直接检查现有源码与项目治理文档（非外部调研），确认每条 FR/SC 的落点与缺口。无 `NEEDS CLARIFICATION` 遗留；唯一的用户决策已在 `/speckit.clarify` 中解决（瞬间启停，不引入加减速过渡）。

## R1 — 视角映射与俯仰限幅

- **Decision**: 沿用 `Camera.look()` 的现有规则：偏航随鼠标水平增量与灵敏度累加并按 2π 取模，俯仰随垂直增量反向变化并钳制在现有上下限内；灵敏度继续由 `0.0025 × 倍率` 映射。
- **Rationale**: `src/engine/renderer/camera.zig:33–42` 已满足 FR-001/002/003，且 `camera.zig:83–107` 已有灵敏度比例测试；保持该实现即可满足 SC-001/002，无需改动渲染或输入层。
- **Alternatives considered**: 新增独立垂直灵敏度或 Y 轴反转——被规格 Assumptions 明确排除（YAGNI），且会改变大厅 UI 契约；拒绝。

## R2 — 移动方向解释与斜向限速

- **Decision**: 训练场移动继续使用 `World.setCharacterInput()`：按相机偏航旋转 strafe/forward，用 `@max(1, sqrt(x²+z²))` 归一化，常规速度 3、冲刺速度 7，输入立即生效、取消时立即归零。
- **Rationale**: `src/engine/physics/world.zig:122–138` 已满足 FR-005/006/007/014；`src/physics_test.zig:137–174` 已覆盖斜向 3m/s、冲刺撞墙与沿墙滑动。保留可避免触碰已验收的物理行为。
- **Alternatives considered**: 复用 `Camera.fly()` 的自由飞行逻辑——飞行模式不经过碰撞、眼高与角色状态，会让训练场失去沿墙滑动与着地判定，违反不变量；拒绝。

## R3 — 鼠标捕获门控与失焦清理

- **Decision**: `Camera.look()` 增加显式捕获门控，调用方仍只在捕获时调用；失焦、Tab 释放鼠标、Esc 返回大厅、回合结束与重开统一调用 `input.releaseAll()` 清理按住状态，暂停/未捕获时 `DemoScene.updateTraining()` 继续调用 `setCharacterInput(null)`。
- **Rationale**: `src/main.zig` 的窗口事件分支与 `src/engine/renderer/demo_scene.zig` 的回合分支现在完整覆盖 FR-004 与 FR-010；`physics_test.zig` 与 `input.zig` 的测试覆盖单次起跳、取消输入与按键状态清理。门控同时保留在 `Camera.look()` 与调用方，避免未来调用方遗漏。
- **Alternatives considered**: 在物理层增加去抖或重复按键过滤——`InputState.pressed()` 边沿与 `jump_pending` 消费已保证单次起跳（FR-008/SC-004），额外过滤会增加延迟与复杂度；拒绝。

## R4 — 会话灵敏度应用时机

- **Decision**: 大厅修改灵敏度后，在进入训练场时经 `applySettings()` → `DemoScene.setSensitivityFromUi()` 应用到相机；回合重开通过 `Camera.resetForRound()` 只重置视角/位置并保留灵敏度，从而在整个会话内保持一致。
- **Rationale**: `src/main.zig` 的设置应用路径与 `camera.zig` 的灵敏度映射满足 FR-003；`resetForRound()` 的单元测试锁定“重开不回退灵敏度”，避免 `camera = .{}` 把倍率悄悄重置为 1.0。
- **Alternatives considered**: 每帧从设置读取灵敏度——增加无必要的状态耦合，且可能让同一帧内不同步骤使用不同倍率；拒绝。

## R5 — 验证策略

- **Decision**: 分层验证——Zig 单测覆盖输入边沿/增量累积与灵敏度映射；`physics-test` 覆盖方向、斜向限速、冲刺、单次跳跃与取消；构建命令验证两种基础模式独立；手动与无桌面冒烟验证捕获/失焦/重开等端到端流程。
- **Rationale**: 对应宪章“测试先行与验收门禁”和项目既有验收基线（README「测试与验收」）；可重复、可防回归。纯手动验收不可重复，无法支撑零回归原则。
- **Alternatives considered**: 仅靠手动验收——不满足 SC-006 的“回归数为 0”可测要求；拒绝。

## R6 — 文档同步

- **Decision**: 更新 `README.md` 的操作/训练场章节与「测试与验收」记录，说明瞬间启停的确认决策；不新增独立设计页到 `docs/`。
- **Rationale**: 宪章要求新增或修改功能时同步 README；本次是有界打磨，现有 README 结构足够承载。
- **Alternatives considered**: 只改代码不改文档——违反治理门禁，且会让已验收记录与行为不一致；拒绝。
