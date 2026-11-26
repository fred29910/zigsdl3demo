# Data Model: 训练模式操控完善

**Feature**: `004-training-mode-controls` | **Date**: 2026-11-26

本特性**不涉及持久化数据**：所有状态都是会话内运行时状态，进程退出即丢失。以下实体描述现有代码中的状态形状、校验规则与状态转换，用于指导测试与接口契约。

## lobby.Settings（会话设置）

- **sensitivity**: 视角灵敏度倍率，`f32`，默认 `1.0`，允许范围 `0.5–2.0`，由 `lobby.clampSensitivity()` 钳制。
- **volume**: 音量，`u8`，默认 `100`，允许范围 `0–100`，由 `lobby.clampVolume()` 钳制。

**Validation rules**: 大厅 UI 写回后立即钳制到边界并给出提示；进入训练场时应用到相机，同一会话内保持不变（含回合重开，FR-003）。

## InputState（输入状态）

- **down**: 每个 `Action` 的当前按住状态。
- **pressed_this_frame / released_this_frame**: 本帧按下/松开边沿；同一帧内的快速点击同时保留按下与松开边沿。
- **mouse_dx / mouse_dy**: 当前帧累积的鼠标相对位移。
- **window**: 关联的 SDL 窗口，用于捕获判定。

**Lifecycle**: `beginFrame()` 清空边沿与鼠标增量但保留按住状态；`handleEvent()` 累积增量并设置边沿；`releaseAll()` 在失焦时清理按住状态；`setMouseCaptured()` 重置鼠标增量。

**Validation rules**: 键盘重复事件不重新触发边沿；失焦后重复按下的键不会重新置为按住（FR-010）。

## Camera（视角状态）

- **position**: 相机位置，训练场中由角色脚点加眼高推导。
- **yaw / pitch**: 偏航与俯仰；偏航按 2π 取模，俯仰钳制在现有上下限内，不会翻转（FR-002）。
- **sensitivity**: 实际角速度系数，`0.0025 × 会话倍率`，在大厅倍率变化时立即重算（FR-003）。

**Validation rules**: 非捕获状态下不接受鼠标增量；回合重开时视角与位置恢复默认，但保留会话灵敏度倍率（FR-003、FR-011）。

## World.CharacterInput（移动指令状态）

- **strafe / forward**: 横向与前向输入，范围 `[-1, 1]`，超界钳制。
- **yaw**: 用于把输入旋转到世界方向的相机偏航。
- **sprint**: 冲刺标志，速度从 3 提升到 7。
- **jump_pressed**: 起跳边沿；在世界内部存为 `jump_pending`，直到被一次物理步消费。

**Validation rules**: 斜向输入按 `@max(1, sqrt(strafe² + forward²))` 归一化，斜向速度不超过单向速度（FR-006）；非有限数值被拒绝；输入为 `null` 时速度立即归零并清除 pending（FR-010/FR-014）。

## 关系与状态转换

```text
lobby.Settings.sensitivity ──应用──> Camera.sensitivity
InputState.mouse_dx/dy ──捕获时──> Camera.yaw/pitch ──> 射线方向
InputState 动作边沿 ──> World.CharacterInput ──> Jolt 角色速度 ──> Camera.position

大厅 ──进入训练──> playing ──Tab/失焦──> paused（输入取消）
playing ──胜负结算──> won/lost ──E──> playing（相机、角色、输入状态重置）
```

**状态一致性约束**: 暂停与失焦时视角不变化、移动立即停止；重开时视角、出生点、着地状态与按键状态一起恢复，不残留上一回合的按住或跳跃 pending（FR-004/010/011/014）。
