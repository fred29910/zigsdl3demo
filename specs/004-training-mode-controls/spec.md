# Feature Specification: 训练模式操控完善

**Feature Branch**: `004-training-mode-controls`

**Created**: 2026-11-26

**Status**: Draft

**Input**: User description: "分析当前项目， 完善训练模式，包括但是不限于 1. 鼠标移动视图 2. 前后左右移动"

## Clarifications

### Session 2026-11-26

- Q: 训练场里按下或松开方向键时，角色应该立刻达到目标速度并立刻停下，还是有一段短暂的加速和减速过渡？ → A: 瞬间启停：按下即全速，松开或失焦立即停止，沿用现有验收标准；不引入加速或减速过渡。

## User Scenarios & Testing *(mandatory)*

<!--
  IMPORTANT: User stories should be PRIORITIZED as user journeys ordered by importance.
  Each user story/journey must be INDEPENDENTLY TESTABLE - meaning if you implement just ONE of them,
  you should still have a viable MVP (Minimum Viable Product) that delivers value.

  Assign priorities (P1, P2, P3, etc.) to each story, where P1 is the most critical.
  Think of each story as a standalone slice of functionality that can be:
  - Developed independently
  - Tested independently
  - Deployed independently
  - Demonstrated to users independently
-->

### User Story 1 - 鼠标视角控制 (Priority: P1)

玩家进入默认训练场并捕获鼠标后，可以用鼠标自然、可控地转动第一人称视角：向右移动鼠标视线向右转，向上移动鼠标视线向上抬；转动幅度与鼠标移动量和当前灵敏度设置一致；到达抬头/低头极限时平稳停住而不会翻转。松开鼠标捕获或窗口失焦时，鼠标移动不再改变视角。

**Why this priority**: 用户明确把“鼠标移动视图”列为首要完善项。视角是射击训练场一切瞄准与移动的基础，必须先做到稳定、可预测。

**Independent Test**: 在大厅把灵敏度调到不同档位，进入训练场捕获鼠标，分别做水平、垂直和到极限的鼠标移动，观察视角变化方向和幅度；再释放鼠标并移动鼠标，确认视角不动。每一步都可在现有训练场中独立演示。

**Acceptance Scenarios**:

1. **Given** 训练场已开始且鼠标已捕获，**When** 玩家向右移动鼠标一段距离，**Then** 视角向右偏转，偏转量与鼠标水平位移及当前灵敏度成正比。
2. **Given** 训练场已开始且鼠标已捕获，**When** 玩家向上移动鼠标，**Then** 视角向上抬起；持续上移到上限后，视角停在上限且不会绕回或翻转。
3. **Given** 大厅中把视角灵敏度设置为 0.5 与 2.0 两档，**When** 在两档下施加完全相同的鼠标位移，**Then** 2.0 档的视角变化量约为 0.5 档的四倍，且方向一致。
4. **Given** 玩家已捕获鼠标并正在转视角，**When** 按 Tab 释放鼠标或窗口失焦，**Then** 后续鼠标移动不再改变视角，已有的视角角度保持不变。

---

### User Story 2 - WASD 地面移动 (Priority: P2)

玩家用 W/A/S/D 相对当前视角方向移动：前进沿视线水平投影方向，后退相反，左右为横向平移；斜向移动的速度不超过单一方向的速度；按住 Shift 冲刺时速度提升；按空格在着地时起跳且按住空格不会连续起跳；靠墙移动可沿墙滑动，回到地面后恢复着地状态。松开按键或失去焦点时，角色停止移动。

**Why this priority**: 用户明确把“前后左右移动”列为第二个完善项。移动手感直接决定训练场是否可玩，且与视角方向强相关，必须在视角可用之后紧接着保证。

**Independent Test**: 在训练场中分别沿八个水平方向（前、后、左、右及四个斜向）移动相同时间，比较位移；再测试冲刺、单次起跳、沿墙滑动和失焦停止。可完全在默认训练场中独立验收，不依赖武器或机器人。

**Acceptance Scenarios**:

1. **Given** 视角朝向任意水平角度，**When** 玩家分别按 W、A、S、D，**Then** 角色分别沿视线前方、左侧、后方、右侧移动，方向与视角一致。
2. **Given** 玩家同时按住两个相邻方向键（例如 W+D），**When** 持续移动相同时间，**Then** 斜向位移不超过单方向位移的 1.05 倍，移动方向与两键的合力方向一致。
3. **Given** 玩家按住 Shift 与 W，**When** 持续移动相同时间，**Then** 位移明显大于不按 Shift 时，速度提升保持稳定。
4. **Given** 玩家站在地面且已着地，**When** 按住空格不放并持续移动，**Then** 角色只起跳一次；松开后再次按下才会再次起跳。
5. **Given** 玩家贴着围墙斜向移动，**When** 持续顶住墙前进，**Then** 角色沿墙滑动而不是穿透或卡死，离开墙后恢复正常移动。
6. **Given** 玩家正按住移动键，**When** 窗口失焦、回合结束或按 Tab 暂停，**Then** 角色在随后的一帧内停止移动，不会继续滑行。

---

### User Story 3 - 控制状态一致与重开 (Priority: P3)

玩家在回合中调整灵敏度、暂停/恢复、以及胜负结算后按 E 重开时，视角与移动控制保持一致且可预测：重开后视角回到出生朝向、角色回到出生点的着地状态、移动与跳跃的按键状态被清空；大厅的灵敏度设置在整个会话中持续生效，且不影响两个基础演示模式的独立运行。

**Why this priority**: 保证前两条故事在完整会话周期内可靠，避免“第一次好用、重开后错乱”的回归，符合项目零回归与确定性状态约束。

**Independent Test**: 先转视角并移动角色，触发回合结束再按 E 重开，核对视角、出生点、着地状态与移动响应；再分别运行 2D 输入演示和 清屏演示模式，确认它们与训练场控制改动互不影响。

**Acceptance Scenarios**:

1. **Given** 玩家已转视角并离开出生点，**When** 回合结束并按 E 重开，**Then** 视角恢复默认朝向，角色回到出生点且处于可移动状态，之前的按住状态不残留。
2. **Given** 大厅中已调整视角灵敏度，**When** 进入训练场、返回大厅、再次进入训练场，**Then** 灵敏度设置保持一致且始终按同一比例作用于视角旋转。
3. **Given** 训练场控制已完善，**When** 分别启动 2D 输入演示与清屏演示模式，**Then** 两个模式仍能独立构建、运行和测试，不依赖训练场的角色与物理控制逻辑。

---

### Edge Cases

<!--
  ACTION REQUIRED: The content in this section represents placeholders.
  Fill them out with the right edge cases.
-->

- 同时按下完全相反的方向键（例如 W+S 或 A+D）时，对应方向的速度相互抵消，角色保持静止。
- 鼠标在单帧内产生极大位移（例如窗口重新捕获、驱动抖动或高轮询率设备）时，视角按同一比例响应并仍受俯仰上限约束，不出现角度跳变到非法值或翻转。
- 视角灵敏度为大厅允许的最大值时，俯仰角仍停留在允许的上下限内，不会越过极点。
- 玩家在移动过程中被击倒、回合结束或主动暂停时，已按住的键位状态被清理；恢复后不会自动继续移动或起跳。
- 捕获鼠标失败（例如窗口不可用）时，视角与移动均不响应，且不留下部分生效的中间状态。

## Requirements *(mandatory)*

<!--
  ACTION REQUIRED: The content in this section represents placeholders.
  Fill them out with the right functional requirements.
-->

### Functional Requirements

- **FR-001**: 系统 MUST 在鼠标捕获状态下，根据鼠标水平位移和当前灵敏度改变视角的偏航角，位移方向与目标转向方向一致。
- **FR-002**: 系统 MUST 在鼠标捕获状态下，根据鼠标垂直位移改变视角的俯仰角，并在到达预设的抬头与低头极限时停止变化，不允许越过极限发生翻转。
- **FR-003**: 系统 MUST 让大厅中选择的角度灵敏度设置在整个会话内一致作用于视角旋转，设置变化后立即生效，且不同档位之间保持确定的比例关系。
- **FR-004**: 系统 MUST 在鼠标未捕获、窗口失焦或训练暂停时忽略鼠标位移，不改变视角角度。
- **FR-005**: 系统 MUST 根据当前视角的水平朝向解释前后左右移动输入，使四个方向键产生与视线一致的平移。
- **FR-006**: 系统 MUST 对同时按下多个方向键的情况进行平衡处理，使任意斜向移动的速度不超过单一方向移动的速度。
- **FR-007**: 系统 MUST 在按住冲刺键时提高移动速度，松开后恢复到常规速度，且速度变化在手感和数值上保持一致。
- **FR-008**: 系统 MUST 让一次起跳按键只触发一次起跳，按住跳跃键不重复触发；仅在角色着地时允许起跳。
- **FR-009**: 系统 MUST 在与障碍或围墙接触时保持沿表面滑动的移动能力，不穿透墙体与障碍，也不会因持续顶墙而卡死。
- **FR-010**: 系统 MUST 在窗口失焦、鼠标释放、暂停或回合结束时清理已按住的移动与跳跃状态，使角色在随后停止移动。
- **FR-011**: 系统 MUST 在回合重开时把视角、角色位置、着地状态和按键状态恢复到确定的初始状态。
- **FR-012**: 系统 MUST 保持两个基础演示模式（2D 输入演示与清屏演示）独立于训练场角色与物理控制逻辑，仍可单独构建、运行与测试。
- **FR-013**: 系统 MUST 为视角与移动控制的关键行为提供可自动运行的验证，覆盖灵敏度映射、斜向速度一致、连续鼠标输入响应与单次起跳判定。
- **FR-014**: 系统 MUST 在按下移动键时立即达到目标移动速度，松开移动键、失焦或暂停时立即停止，不引入加速或减速过渡。

## Success Criteria *(mandatory)*

<!--
  ACTION REQUIRED: Define measurable success criteria.
  These must be technology-agnostic and measurable.
-->

### Measurable Outcomes

- **SC-001**: 在灵敏度允许的整个区间内，相同鼠标位移产生的视角变化方向 100% 正确，变化量与位移和灵敏度成比例（幅度误差不超过 10%）。
- **SC-002**: 视角俯仰在预设上下限之间连续可调，达到上限或下限后保持不动；连续 100 次达到极限的鼠标输入中，越界或翻转次数为 0。
- **SC-003**: 八个水平移动方向中，任意斜向位移与单一方向位移的差异不超过 5%。
- **SC-004**: 连续 10 次按下并按住跳跃键，恰好产生 10 次起跳，重复触发次数为 0；仅在着地状态下起跳。
- **SC-005**: 失焦、释放鼠标或回合结束后的一帧内，持续按住移动键的角色位移归零，没有可观察的继续滑行。
- **SC-006**: 回合重开后视角、出生点、着地状态与移动响应恢复到与首次进入一致；2D 演示与清屏演示的配置构建和既有测试全部通过，回归数为 0。

## Assumptions

<!--
  ACTION REQUIRED: The content in this section represents placeholders.
  Fill them out with the right assumptions based on reasonable defaults
  chosen when the feature description did not specify certain details.
-->

- 用户所说的“完善”是在已有功能基础上的打磨：项目当前已经具备鼠标转视角、WASD 移动、冲刺、跳跃、沿墙滑动、灵敏度设置和失焦暂停；“包括但是不限于”中的两项是优先级最高的完善对象，而不是从零新增。
- 本次完善限定在训练场的视角与移动操控及直接相关的状态一致性；不扩展到新增武器、敌人、关卡、联网或排行榜等玩法内容。
- 视角俯仰上下限沿用项目现有设定，灵敏度沿用大厅现有的倍率区间与默认值；这些是用户可观察的既有约定，本次不擅自发明新配置或新的角色属性。
- 不引入投机性新开关（如独立的垂直灵敏度、Y 轴反转、蹲伏移动）；除非用户明确提出，这些不属于本次有界改动范围。
- 物理与相机的既有验收约定保持不变，任何改动都不修改这些已验收的行为参数。
- 验收沿用项目既有的虚拟显示与软件渲染基线；真实桌面窗口管理器与物理播放设备仍不在已验证范围内。
