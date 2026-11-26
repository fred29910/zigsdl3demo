---

description: "Tasks for 游戏大厅界面"
---

# Tasks: 游戏大厅界面

**Input**: Design documents from `/specs/001-game-lobby-ui/`

**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/, ui-design.md, quickstart.md

**Tests**: 测试为可选；本规格未要求新增产品测试文件。按宪章 II 的 Red-Green-Refactor，先执行 `quickstart.md` V1–V6 / `contracts/acceptance-gates.md` G1–G5 并确认当前状态失败（RED），再实现；既有门禁为唯一判定依据。

**Organization**: Tasks are grouped by user story to enable independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- 单项目仓库：`src/`、`assets/`、`build.zig.zon`、`README.md` 位于根目录；设计文档位于 `specs/001-game-lobby-ui/`
- 禁止编辑 `zig-pkg/`、`zig-out/`、`.zig-cache/`；不改 HLSL/SPIR-V

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: 固定基线、门禁与中文字体资源

- [X] T001 运行 `zig version` 与 `git status`，确认 Zig 精确为 0.17.1、工作树状态已知；按 `specs/001-game-lobby-ui/plan.md` 确认改动范围，将基线记入 `specs/001-game-lobby-ui/research.md`
- [X] T002 [P] 按 `specs/001-game-lobby-ui/contracts/acceptance-gates.md` 执行并记录 G1–G5 基线（命令 `zig build install test` / `zig build install test -Doptimize=ReleaseSafe` / `zig build physics-test` / `zig build test -Ddemo-2d=true` / `zig build test -Dclear-only=true`）；记录 `data-model.md` `验收门禁.名称`、`验收门禁.命令`、`验收门禁.结果` 到 `specs/001-game-lobby-ui/contracts/acceptance-gates.md`
- [X] T003 [P] 将 Noto Sans SC（OFL）Regular + Bold 中文子集字体放入 `assets/`，并在 `build.zig.zon` 的 `.paths` 中纳入；字体加载契约见 `specs/001-game-lobby-ui/research.md` R5 与 `specs/001-game-lobby-ui/contracts/lobby-ui.md`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: 建立所有故事共用的大厅状态机、UI 入口与不可改动边界

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 [P] 新建 `src/engine/gameplay/lobby.zig`，定义 `LobbySession` 结构及状态枚举，字段对应 `data-model.md` `大厅会话.当前界面`（枚举：大厅/四模式/预览）、`大厅会话.最后选择的模式`（枚举）、`大厅会话.会话设置`（关联 `SessionSettings`）、`大厅会话.当前提示`（可空中文字符串）
- [X] T005 [P] 在 `src/engine/renderer/imgui_bridge.cpp` 的 `demo_imgui_init` 附近加入中文字体加载，并新增大厅绘制入口骨架（与 `demo_imgui_prepare` 并列，不改既有 HUD/Init/Shutdown）；文案与控件见 `specs/001-game-lobby-ui/contracts/lobby-ui.md`
- [X] T006 [P] 复核 `src/main.zig` 四个模式入口与 `build.zig:53` 的 `if (!demo_2d and !clear_only)` 守护，将不可改动项与 `data-model.md` `运行模式.可观察结果` 的对照结论写入 `specs/001-game-lobby-ui/research.md` R1/R6
- [X] T007 在 `specs/001-game-lobby-ui/contracts/acceptance-gates.md` 固定 G1–G5 与 V1–V6 判定规则、失败修复后重跑、不放宽门禁；字段依据 `data-model.md` `验收门禁.结果`
- [X] T008 [P] 在 `README.md`「操作与训练场」「运行模式与构建」预留大厅说明与 Esc 语义更新位置，模式名称以 `data-model.md` `运行模式.中文名称` 与 `specs/001-game-lobby-ui/contracts/lobby-ui.md` 为准

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - 启动后从大厅一键进入训练场 (Priority: P1) 🎯 MVP

**Goal**: 启动先显示可交互中文大厅，「开始训练」一次选择进入默认内嵌训练场；模式内 Esc 返回、大厅内 Esc 不退出、退出按钮/关窗才退出。

**Independent Test**: 仅实现本故事时，`zig build run` 先显示大厅；一次点击「开始训练」进入默认训练场并完成 README 基础流程；模式内 Esc 返回大厅、大厅内 Esc 无动作；满足 SC-001。

### Implementation for User Story 1

- [X] T009 [US1] 按 `specs/001-game-lobby-ui/quickstart.md` V1/V2 在当前状态执行并确认 RED（无大厅、Esc 直接退出），将失败结果记入 `specs/001-game-lobby-ui/contracts/acceptance-gates.md`
- [X] T010 [US1] 在 `src/main.zig` 顶层循环加入大厅前置状态：启动时把 `data-model.md` `大厅会话.当前界面` 设为大厅，默认训练场仅在其明确确认后启动（FR-001）
- [X] T011 [US1] 在 `src/engine/gameplay/lobby.zig` 实现「开始训练」入口：一次选择进入默认内嵌训练场，依据 `data-model.md` `运行模式.入口标识` 与 `运行模式.可观察结果`
- [X] T012 [US1] 在 `src/main.zig` 复用 `DemoScene.init`/`DemoScene.deinit` 完成模式进入与返回，更新 `data-model.md` `大厅会话.最后选择的模式`，不改动玩法与 HUD（FR-002/FR-011）
- [X] T013 [US1] 在 `src/main.zig` 把 `main.zig:116` 的 Esc 分支改为按 `data-model.md` `大厅会话.当前界面` 分派：模式内返回大厅并释放该模式资源（`运行模式.资源释放`），大厅内忽略 Esc；退出仅由「退出」按钮与窗口关闭事件触发
- [X] T014 [US1] 在 `src/engine/renderer/imgui_bridge.cpp` 绘制大厅默认态与固定页脚文案（「大厅内按 Esc 不会退出」「退出」），文案逐字取自 `specs/001-game-lobby-ui/contracts/lobby-ui.md`
- [ ] T015 [US1] 验证 `specs/001-game-lobby-ui/quickstart.md` V1/V2 与 `specs/001-game-lobby-ui/ui-design.md` D-01/D-02/D-11，将结果写入 `specs/001-game-lobby-ui/contracts/acceptance-gates.md`

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently

---

## Phase 4: User Story 2 - 从大厅选择其他运行模式并返回 (Priority: P1)

**Goal**: 大厅列出四个模式并一次选择进入；外部模型预览在专门界面用文本输入收集路径；返回大厅释放资源、无状态残留；初始化失败可读提示并停留大厅。

**Independent Test**: 逐个选择四个模式均能进入并呈现特有画面；Esc 返回大厅后二次进入无残留；无效路径与初始化失败均给出可读反馈且程序可继续（SC-002/SC-004）。

### Implementation for User Story 2

- [X] T016 [US2] 在 `src/engine/gameplay/lobby.zig` 登记四个模式的 `data-model.md` `运行模式.中文名称`、`运行模式.入口标识`、`运行模式.可观察结果`、`运行模式.失败处理`，与 `specs/001-game-lobby-ui/contracts/lobby-ui.md` 文案一致
- [X] T017 [US2] 在 `src/engine/gameplay/lobby.zig` 与 `src/engine/renderer/imgui_bridge.cpp` 实现同窗替换的外部模型预览主体：全宽路径文本输入（可粘贴）、「加载模型」「返回大厅」按钮，确认后复用现有 GLB/glTF 加载路径
- [X] T018 [US2] 在 `src/engine/gameplay/lobby.zig` 实现路径无效/格式不支持/依赖缺失的可读错误，写入 `data-model.md` `大厅会话.当前提示` 并按 `运行模式.失败处理` 允许返回大厅；错误文案取自 `specs/001-game-lobby-ui/contracts/lobby-ui.md`
- [X] T019 [US2] 在 `src/main.zig` 与 `src/engine/gameplay/lobby.zig` 实现任一模式返回时的资源释放与状态清理，依据 `data-model.md` `运行模式.资源释放`，保证二次进入无角色/靶板/机器人/模型残留
- [X] T020 [US2] 在 `src/engine/gameplay/lobby.zig` 实现初始化失败（图形/音频/模型）时停留大厅、显示可读错误、可重试或改选，依据 `data-model.md` `运行模式.失败处理` 与 `大厅会话.当前提示`（FR-012）
- [X] T021 [US2] 在 `src/engine/gameplay/lobby.zig` 实现单次确认锁与 250ms 冷却：初始化前以最后确认的模式为准、初始化后忽略后续输入、不排队，遵循 `specs/001-game-lobby-ui/ui-design.md` 4.5 与规格 Edge Cases
- [ ] T022 [US2] 验证 `specs/001-game-lobby-ui/quickstart.md` V3/V4 与 `specs/001-game-lobby-ui/ui-design.md` D-04/D-06/D-07/D-09/D-10/D-12，结果写入 `specs/001-game-lobby-ui/contracts/acceptance-gates.md`

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently

---

## Phase 5: User Story 3 - 在大厅调整基础设置 (Priority: P2)

**Goal**: 视角灵敏度与音量在大厅可调、实时显示、会话内生效、非法值收敛并提示；重启恢复默认。

**Independent Test**: 调整两项设置并进入场景可观察变化；越界/空/非数字输入给出可读提示并收敛到允许范围边界；重启恢复默认（SC-006）。

### Implementation for User Story 3

- [X] T023 [US3] 在 `src/engine/gameplay/lobby.zig` 定义 `SessionSettings` 及默认值，字段依据 `data-model.md` `会话设置.视角灵敏度`（float，0.5–2.0，默认 1.0，步长 0.05）与 `会话设置.音量`（int，0–100，默认 100）；不写磁盘
- [X] T024 [US3] 在 `src/engine/renderer/camera.zig` 增加 `sensitivity: f32` 字段并在 `look` 中替换硬编码 `0.0025`，进入场景时按默认 1.0 等效注入，依据 `data-model.md` `会话设置.视角灵敏度`
- [X] T025 [US3] 在 `src/engine/audio/demo_audio.zig` 与 `src/engine/audio/miniaudio_bridge.c` 增加音量设置包装（0–100 → 0.0–1.0），依据 `data-model.md` `会话设置.音量`，不改变既有音效生成与播放流程
- [X] T026 [US3] 在 `src/engine/renderer/imgui_bridge.cpp` 绘制两项设置控件、实时数值与常驻范围提示，文案与布局取自 `specs/001-game-lobby-ui/contracts/lobby-ui.md`，字段依据 `data-model.md` `会话设置.视角灵敏度`、`会话设置.音量`
- [X] T027 [US3] 在 `src/engine/gameplay/lobby.zig` 实现非法输入收敛：空/非数字恢复上次有效值、越界收敛到最近边界并写入 `data-model.md` `大厅会话.当前提示` 的可读中文提示，非法值不进入场景
- [ ] T028 [US3] 验证 `specs/001-game-lobby-ui/quickstart.md` V5 与 `specs/001-game-lobby-ui/ui-design.md` D-08/D-18（含重启恢复默认），结果写入 `specs/001-game-lobby-ui/contracts/acceptance-gates.md`

**Checkpoint**: All user stories should now be independently functional

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: 文档同步、全量门禁、提交与端到端复核

- [X] T029 [P] 更新 `README.md` 操作表（Esc 改为「模式内返回大厅、大厅内不退出」）、大厅与模式名称说明、字体许可说明，并引用 `specs/001-game-lobby-ui/ui-design.md` D-01–D-18
- [X] T030 执行 `specs/001-game-lobby-ui/contracts/acceptance-gates.md` 的 G1–G5 全量门禁，并按 `specs/001-game-lobby-ui/quickstart.md` 完成 V1–V6 端到端复核，结果记入 `specs/001-game-lobby-ui/contracts/acceptance-gates.md`
- [X] T031 审阅完整 diff：确认未触碰 `shaders/`、`assets/range.glb`、`assets/demo.glb`、`src/physics_test.zig`，`build.zig:53` 守护不变；按宪章以 `feat:`/`docs:` 前缀与中文描述原子提交
- [ ] T032 [P] 按 `specs/001-game-lobby-ui/ui-design.md` 的 D-01–D-18 做最终逐项复核，任何缺字、重叠或 Esc 异常回到对应故事任务修复

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3+)**: All depend on Foundational phase completion
  - US1（P1）先建立大厅入口与 Esc 路由；US2（P1）依赖 US1 的状态机与 Esc 路由；US3（P2）依赖 US1/US2 的会话与场景接入
- **Polish (Final Phase)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P1)**: Depends on US1（`LobbySession` 与 Esc 分派）；四个模式与预览界面可独立验证
- **User Story 3 (P2)**: Depends on US1/US2 的场景进入路径；设置仅在会话内生效，可最后交付

### Within Each User Story

- 先按 `quickstart.md` 确认当前失败（RED）→ 实现 → 验证场景通过（GREEN）
- 同一文件内的改动按任务顺序串行（`src/main.zig`、`lobby.zig`、`imgui_bridge.cpp`）
- 任何门禁失败都必须修复后重跑，不得降低验收标准或改变玩法

### Parallel Opportunities

- T002 与 T003 可并行（门禁记录 vs 字体资源）
- Phase 2 的 T004/T005/T006/T008 可并行（不同文件），T007 依赖 T002 结果
- US1 中 T014 可与 T010–T013 并行（绘制入口与状态机），其余围绕 `main.zig`/`lobby.zig` 串行
- US2 中 T017 与 T018 可并行（UI 绘制 vs 错误逻辑）；T016/T019/T020/T021 围绕同一状态机串行
- US3 中 T024 与 T025 可并行（相机 vs 音频）；T026/T027 围绕 UI/状态机串行
- T029 与 T032 可并行（文档 vs 复核）

---

## Parallel Example: User Story 1

```bash
# 状态机与 UI 可并行（不同文件；先完成 Phase 2）：
Task: "T010 src/main.zig 启动前置大厅状态"
Task: "T014 src/engine/renderer/imgui_bridge.cpp 绘制大厅默认态与页脚"
# 随后串行完成：
Task: "T011-T013 lobby.zig 主入口 → main.zig 场景进入 → Esc 分派"
```

## Parallel Example: User Story 2

```bash
# 并行：
Task: "T017 lobby.zig + imgui_bridge.cpp 预览界面"
Task: "T018 lobby.zig 路径错误提示逻辑"
# 随后串行完成模式登记、资源释放、失败处理、防抖
```

## Parallel Example: User Story 3

```bash
# 并行：
Task: "T024 src/engine/renderer/camera.zig 灵敏度参数"
Task: "T025 src/engine/audio/{demo_audio.zig,miniaudio_bridge.c} 音量接口"
# 随后串行完成 UI 控件与非法输入收敛
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: `zig build run` 先显示大厅，一次进入训练场，Esc 返回大厅，V1/V2 通过
5. 此时大厅核心路径已可用；用户可见的模式选择与设置价值在 US2/US3 增量交付

### Incremental Delivery

1. Complete Setup + Foundational → 状态机、中文字体与 UI 入口就绪
2. Add US1 → 启动大厅 + 一键训练 + Esc/退出（MVP!）
3. Add US2 → 四模式选择、外部模型预览、失败处理与防抖
4. Add US3 → 两项会话设置与非法输入收敛
5. Polish → README 同步、全量门禁与 D-01–D-18 复核

### Parallel Team Strategy

1. 团队共同完成 Setup + Foundational
2. Foundational 完成后：开发者 A 做 US1（依赖 Esc 路由），A 完成后 B 做 US2，C 可做 US3 的相机/音频参数（T024/T025 与 US2 不共享文件）
3. 各故事按 Checkpoint 独立验证，最后合并复核

---

## Notes

- 标记 **[P]** 的任务 = different files, no dependencies
- 标记 **[Story]** 的标签 maps task to specific user story for traceability
- 未在规格中要求新增测试文件；RED/GREEN 以既有门禁与端到端场景为准
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Avoid: vague tasks, same file conflicts, cross-story dependencies that break independence
