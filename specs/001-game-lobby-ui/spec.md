# Feature Specification: 游戏大厅界面

**Feature Branch**: `001-game-lobby-ui`

**Created**: 2026-11-25

**Status**: Draft

**Input**: User description: "分析当前项目情况， 开始完成游戏大厅界面的搭建"

## Clarifications

### Session 2026-11-25

- Q: 在大厅里，用户通过什么方式指定要查看的外部模型文件？ → A: 大厅不指定模型；用户从大厅进入专门的外部模型预览界面，在该界面通过文本输入方式填写或粘贴本地路径并确认，从而预览外部模型。
- Q: 当某个模式无法启动（例如图形设备不可用或音频设备缺失）时，用户应该看到什么？ → A: 显示可读错误信息并停留在大厅，允许重试或选择其他模式。
- Q: 在训练场或其他模式中，用户按什么键或执行什么操作可以返回大厅？ → A: 模式中按 Esc 返回大厅；大厅内 Esc 不退出程序，程序退出由大厅中的退出按钮触发。

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

### User Story 1 - 启动后从大厅一键进入训练场 (Priority: P1)

用户启动程序后先看到一个中文游戏大厅，而不是直接进入 3D 场景。大厅提供明确的「开始训练」入口；用户选择后立即进入默认内嵌训练场，操作方式与现有训练场完全一致。这是大厅的最小可用价值：在不改变玩法的前提下，为后续模式选择与设置提供统一入口。

**Why this priority**: 没有这个入口，大厅就不成立；它是唯一必须优先交付的独立可测试切片。

**Independent Test**: 仅实现本故事时，启动程序应显示大厅，执行一次「开始训练」后进入默认训练场，并能完成 README 中「按 Tab 开始、移动、开火、重开、退出」的基础流程。

**Acceptance Scenarios**:

1. **Given** 程序尚未启动，**When** 用户启动程序，**Then** 首先显示大厅界面而非 3D 场景，且大厅为可交互状态
2. **Given** 大厅已显示，**When** 用户选择「开始训练」，**Then** 进入默认内嵌训练场，窗口尺寸、HUD、调试面板与操作提示与现有默认模式一致
3. **Given** 已进入训练场，**When** 用户按 Esc，**Then** 返回大厅且不退出程序，不出现卡死或重复窗口
4. **Given** 用户在任一时刻关闭大厅窗口，**When** 窗口关闭事件触发，**Then** 程序干净退出，无残留窗口与资源占用
5. **Given** 大厅已显示，**When** 用户在大厅内按 Esc，**Then** 程序不退出且仍停留在大厅；**When** 用户点击「退出」按钮，**Then** 程序干净退出

---

### User Story 2 - 从大厅选择其他运行模式并返回 (Priority: P2)

用户希望在大厅中看到当前工程支持的全部运行模式，并能从中选择一个直接进入，而不需要记忆命令行参数。模式包括：默认训练场、外部模型查看、2D 输入演示、Vulkan 清屏演示。其中外部模型查看由大厅进入专门的预览界面，模型路径在该界面内通过文本输入方式指定，大厅本身不收集模型路径。用户从任一模式退出后应回到大厅，以便继续尝试其他模式。

**Why this priority**: 这些模式已经存在且有验收记录；把它们收拢到大厅能显著降低使用门槛，但不影响 P1 的核心进入路径。

**Independent Test**: 仅实现本故事时，大厅应列出全部四个模式，逐个选择都能进入对应模式并观察到该模式特有的画面或反馈，退出后回到大厅。

**Acceptance Scenarios**:

1. **Given** 大厅已显示，**When** 用户查看模式列表，**Then** 四个现有模式均以中文名称呈现，且名称与 README 中的模式叫法一致
2. **Given** 用户在大厅选择「外部模型预览」入口，**When** 进入专门的预览界面并通过文本输入框填写或粘贴有效的本地 GLB/glTF 路径后确认，**Then** 该界面加载模型并进入自由飞行查看，行为与现有命令行传入路径时一致；大厅本身不提供模型路径输入
3. **Given** 用户选择「2D 输入演示」或「Vulkan 清屏演示」，**When** 进入对应模式，**Then** 分别呈现 2D 输入反馈与固定色清屏，且不初始化其他模式不需要的能力
4. **Given** 用户处于任一非大厅模式，**When** 用户按 Esc，**Then** 回到大厅且该模式的资源被释放，再次进入同一模式不出现状态残留

---

### User Story 3 - 在大厅调整基础设置 (Priority: P3)

用户希望在大厅中调整两项最常用的体验设置——视角灵敏度和音量，并在本次使用会话内立即生效，无需重启程序或编辑配置文件。

**Why this priority**: 提升易用性，但依赖大厅与主流程已经稳定，因此排在最后。

**Independent Test**: 仅实现本故事时，用户可在大厅调整两项设置、看到当前值，并在随后进入的场景中观察到设置已生效。

**Acceptance Scenarios**:

1. **Given** 大厅已显示，**When** 用户调整视角灵敏度，**Then** 界面显示当前数值，进入场景后鼠标转动速度相应变化
2. **Given** 大厅已显示，**When** 用户调整音量，**Then** 界面显示当前数值，进入含音效的场景后音量相应变化
3. **Given** 用户输入超出允许范围的数值，**When** 数值被确认，**Then** 系统给出可读提示并自动收敛到允许范围，不导致界面失效或程序异常
4. **Given** 用户关闭并重新启动程序，**When** 再次查看大厅，**Then** 设置恢复为默认值（本版本不持久化，见 Assumptions）

---

### Edge Cases

<!--
  ACTION REQUIRED: The content in this section represents placeholders.
  Fill them out with the right edge cases.
-->

- 用户提供的外部模型路径不存在、指向不支持的格式或依赖的 `.bin`/纹理缺失时，预览界面必须显示可读错误并允许返回大厅，不得直接退出程序。
- 窗口在大厅状态下被缩放或最小化再恢复时，界面元素必须重新排布且仍可点击，不出现控件重叠或不可见。
- 用户在大厅连续快速点击多个模式入口时，必须只进入最后确认的一个模式，不出现多次初始化或窗口冲突。
- 设置值为空、非数字或超出范围时，必须按「收敛到默认值 + 提示」处理，不接受非法值进入场景。
- 无音频输出设备时，音量设置仍可调整且进入场景后仅记录提示，不影响大厅与场景可用性。
- 从任一模式返回大厅后再次进入同一模式，不得重复累积资源或保留上一局的角色、靶板与机器人状态。
- 任一模式初始化失败（图形设备不可用、音频设备缺失或模型加载失败）时，显示可读错误并停留在大厅，用户可重试或改选其他模式，程序不退出。
- 在大厅内按 Esc 不得退出程序或误触发模式启动；只有点击「退出」按钮或关闭窗口才会退出。

## Requirements *(mandatory)*

<!--
  ACTION REQUIRED: The content in this section represents placeholders.
  Fill them out with the right functional requirements.
-->

### Functional Requirements

- **FR-001**: 系统 MUST 在程序启动时首先呈现大厅界面，且默认训练场仅在大厅明确确认后才启动。
- **FR-002**: 大厅 MUST 提供一个中文标注的「开始训练」入口，选择后进入默认内嵌训练场。
- **FR-003**: 大厅 MUST 展示当前工程支持的全部四个运行模式，并允许每个模式通过一次选择直接进入。
- **FR-004**: 大厅 MUST 提供进入专门外部模型预览界面的入口；该界面 MUST 允许用户通过文本输入方式指定本地模型路径，并对无效路径给出可读错误提示。大厅本身不提供模型路径输入。
- **FR-005**: 系统 MUST 支持从任一非大厅模式返回大厅，返回后该模式的运行状态与资源不得影响下一次进入。
- **FR-006**: 大厅 MUST 提供视角灵敏度与音量的调整入口，并实时显示当前数值。
- **FR-007**: 设置值 MUST 在本次会话内对随后进入的场景生效，且对非法输入具有收敛与提示行为。
- **FR-008**: 大厅 MUST 提供明确的「退出」按钮用于退出程序，并支持通过关闭窗口退出；大厅内 Esc 不得退出程序。任一模式内按 Esc MUST 返回大厅而非退出程序。
- **FR-009**: 大厅及所有模式内的用户可见文本 MUST 使用中文，并与 README 中已有术语保持一致。
- **FR-010**: 大厅 MUST 在大厅状态下响应窗口尺寸变化，保持所有控件可见且可操作。
- **FR-011**: 本次功能 MUST 保持现有四个模式的可观察行为与其验收记录一致，除进入与退出路径外不得改变玩法。
- **FR-012**: 系统 MUST 在任一模式初始化失败时显示可读错误并停留在大厅，允许重试或选择其他模式，不得直接退出程序。

### Key Entities *(include if feature involves data)*

- **大厅会话**: 一次从启动到退出的使用过程，记录当前所处界面（大厅或某一模式）、用户最后选择的模式与两项设置的当前值；本版本不跨会话保存。
- **运行模式**: 一个可独立进入的体验入口，包含中文名称与进入后应呈现的可观察结果；共四个，与现有 README 中的运行模式一一对应。
- **会话设置**: 视角灵敏度与音量两项数值，具有允许范围、默认值与本次会话内的生效语义。

## Success Criteria *(mandatory)*

<!--
  ACTION REQUIRED: Define measurable success criteria.
  These must be technology-agnostic and measurable.
-->

### Measurable Outcomes

- **SC-001**: 用户从启动程序到开始操作训练场，不超过两次明确选择，且在现有验收机器上耗时低于 3 秒。
- **SC-002**: 大厅列出的运行模式数量与 README 记录一致（4 个），且每个模式都能通过一次选择进入并呈现其特有画面。
- **SC-003**: 从大厅进入任一模式后，README「手动验收」清单中对应条目保持通过，命中判定、武器参数、机器人行为与结算重开结果不发生变化。
- **SC-004**: 无效外部模型路径、非法设置值、窗口缩放与模式初始化失败四类异常场景中，100% 给出可读反馈且程序保持可继续操作。
- **SC-005**: 引入大厅后，项目现有的全部自动化测试与验收流程保持通过，不新增外部依赖。
- **SC-006**: 设置调整后，用户在随后场景中可观察到对应变化，无需重新启动程序。

## Assumptions

<!--
  ACTION REQUIRED: The content in this section represents placeholders.
  Fill them out with the right assumptions based on reasonable defaults
  chosen when the feature description did not specify certain details.
-->

- 当前工程已有的四个运行模式（默认训练场、外部模型查看、2D 输入演示、Vulkan 清屏演示）即为大厅需要收拢的全部模式；不新增第五种模式。
- 大厅作为启动后的入口界面新增，首次交付不改变任何模式内部的操作、HUD 与验收行为。
- 「游戏大厅」指本地单用户菜单界面，不涉及联网、账号、匹配或多人房间。
- 退出约定：在任一模式中按 Esc 返回大厅；大厅内 Esc 不退出程序，程序退出仅通过大厅中的「退出」按钮或关闭窗口触发。该变更需要在实现时同步更新 README 操作表与验收清单。
- 设置仅在本会话内生效，不写入磁盘；默认值沿用当前程序内的既有行为，避免引入持久化带来的额外范围。
- 界面文案为中文，与 README 现有术语一致；数值范围以不破坏现有操作手感与听感为原则。
- 验收基线仍是 Linux 桌面与虚拟显示环境；大厅可用性需在窗口缩放与关闭路径上验证。
