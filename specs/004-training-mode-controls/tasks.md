# Tasks: 训练模式操控完善

**Input**: Design documents from `/specs/004-training-mode-controls/`

**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: 本特性包含测试任务，因为 spec.md 的 FR-013 明确要求“为视角与移动控制的关键行为提供可自动运行的验证”，且宪章原则 II 要求测试先行。

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Single project**: `src/` at repository root（本仓库采用此结构）
- 路径均相对仓库根目录；不修改 `zig-pkg/`、`zig-out/`、`.zig-cache/`

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: 确认工具链、绿色基线与代码落点，为后续任务提供一致起点

- [X] T001 在仓库根目录运行 `zig version`（必须为 0.17.1）与 `zig build install test`，确认 build.zig 的精确版本校验与 README.md 快速开始一致，记录当前为绿色基线
- [X] T002 [P] 对照 specs/004-training-mode-controls/plan.md、research.md 与 data-model.md 核对会话设置约束（data-model.md `lobby.Settings.sensitivity`：0.5–2.0、默认 1.0；data-model.md `lobby.Settings.volume`：0–100、默认 100）未发生变化，并定位 src/engine/gameplay/lobby.zig、src/engine/renderer/camera.zig、src/engine/platform/sdl/input.zig、src/engine/physics/world.zig、src/engine/renderer/demo_scene.zig 中与 FR 相关的现有实现，记录差距但不修改代码

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: 建立 US1/US3 与 US2/US3 共用的测试辅助，避免重复构造逻辑

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T003 [P] 在 src/engine/platform/sdl/input.zig 的测试区补充可复用的鼠标运动与按键事件构造辅助（供 US1、US3 复用），保持 Action 映射与本帧边沿语义不变
- [X] T004 [P] 在 src/physics_test.zig 补充可复用的最小地面/围墙与角色构造辅助（供 US2、US3 复用），保持既有测试与物理参数不变

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - 鼠标视角控制 (Priority: P1) 🎯 MVP

**Goal**: 捕获鼠标后可按位移与灵敏度自然转向，俯仰到极限停住不翻转，释放或失焦后视角不再响应。

**Independent Test**: 在大厅设两档灵敏度进入训练场，施加相同鼠标位移比较转向幅度；持续上移到极限观察停住；释放鼠标后再移动鼠标确认视角不变（对应 SC-001、SC-002 与 US1 验收场景）。

### Tests for User Story 1

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T005 [P] [US1] 在 src/engine/renderer/camera.zig 添加视角测试：相同鼠标位移下偏航方向与幅度随灵敏度成比例（data-model.md `Camera.yaw`、data-model.md `Camera.sensitivity`），向上移动鼠标使俯仰增大且视线朝上（data-model.md `Camera.pitch`），并验证俯仰到极限后不再变化；先运行确认失败
- [X] T006 [P] [US1] 在 src/engine/platform/sdl/input.zig 添加鼠标增量测试：同帧多次 mouse_motion 累加 `InputState.mouse_dx` 与 `InputState.mouse_dy`（data-model.md `InputState.mouse_dx`、data-model.md `InputState.mouse_dy`），`beginFrame()` 与 `setMouseCaptured()` 清零增量，窗口关联见 data-model.md `InputState.window`；先运行确认失败

### Implementation for User Story 1

- [X] T007 [US1] 在 src/engine/renderer/camera.zig 与 src/engine/renderer/demo_scene.zig 收紧视角行为：保留 `Camera.look()` 的偏航取模、俯仰钳制与灵敏度映射，确保 `updateTraining()` 仅在 captured 时调用 look，相机位置继续由角色脚点加眼高推导（data-model.md `Camera.position`）；依赖 T005、T006
- [X] T008 [US1] 运行 `zig build install test` 验证 US1 测试全部通过（src/engine/renderer/camera.zig、src/engine/platform/sdl/input.zig）

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently

---

## Phase 4: User Story 2 - WASD 地面移动 (Priority: P2)

**Goal**: WASD 相对视线移动、斜向限速、冲刺提速、单次起跳、沿墙滑动，按下即全速松开即停。

**Independent Test**: 在 src/physics_test.zig 中比较四方向与斜向位移、冲刺速度、按住空格的起跳次数，以及瞬间启停与沿墙滑动（对应 SC-003、SC-004 与 US2 验收场景）。

### Tests for User Story 2

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T009 [P] [US2] 在 src/physics_test.zig 添加方向与斜向测试：相对 yaw 的前/左/后/右移动，斜向位移不超过单向的 1.05 倍，按下即达到目标速度、取消输入立即停止（data-model.md `World.CharacterInput.strafe`、data-model.md `World.CharacterInput.forward`、data-model.md `World.CharacterInput.yaw`）；先运行确认失败
- [X] T010 [P] [US2] 在 src/physics_test.zig 添加冲刺与起跳测试：按住 sprint 速度提升（data-model.md `World.CharacterInput.sprint`），按住空格只起跳一次且松开再按才再次起跳（data-model.md `World.CharacterInput.jump_pressed`），并保留既有沿墙滑动断言；先运行确认失败

### Implementation for User Story 2

- [X] T011 [US2] 在 src/engine/physics/world.zig 收紧 `World.setCharacterInput()`：保持 strafe/forward 钳制与 `@max(1, sqrt(x²+z²))` 归一化、常规速度 3 与冲刺 7、非有限输入拒绝、输入为 null 时速度归零并清除 pending（data-model.md `World.CharacterInput.strafe`、data-model.md `World.CharacterInput.forward`、data-model.md `World.CharacterInput.sprint`、data-model.md `World.CharacterInput.jump_pressed`），不引入加减速过渡（FR-014）；依赖 T009、T010（核对现有实现已满足，无需改代码）
- [X] T012 [US2] 运行 `zig build physics-test` 验证 US2 测试全部通过（src/physics_test.zig、src/engine/physics/world.zig）

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently

---

## Phase 5: User Story 3 - 控制状态一致与重开 (Priority: P3)

**Goal**: 失焦、暂停、回合结束与重开时视角和移动状态被确定性地清理与恢复，灵敏度在会话内保持一致，两个基础演示模式不受影响。

**Independent Test**: 在 src/engine/platform/sdl/input.zig 与 src/physics_test.zig 验证失焦清理与取消输入；再运行两种基础模式测试与重开流程（对应 SC-005、SC-006 与 US3 验收场景）。

### Tests for User Story 3

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T013 [P] [US3] 在 src/engine/platform/sdl/input.zig 添加失焦清理测试：`releaseAll()` 清空按住状态并保留本帧边沿，键盘 repeat 不会重新置为按住（data-model.md `InputState.down`、data-model.md `InputState.pressed_this_frame`、data-model.md `InputState.released_this_frame`）；先运行确认失败
- [X] T014 [P] [US3] 在 src/physics_test.zig 添加取消测试：`setCharacterInput(null)` 后速度归零且跳跃 pending 清除（data-model.md `World.CharacterInput.jump_pressed`）；先运行确认失败

### Implementation for User Story 3

- [X] T015 [US3] 在 src/engine/renderer/demo_scene.zig 与 src/main.zig 收紧状态一致性：暂停/未捕获时继续调用 `setCharacterInput(null)`，Tab 释放/Esc/回合结束/重开时清理按住状态，回合重开经 `Camera.resetForRound()` 重置视角与位置但保留会话灵敏度，进入训练场时应用会话灵敏度（data-model.md `lobby.Settings.sensitivity`、data-model.md `Camera.sensitivity`、data-model.md `Camera.position`）；依赖 T013、T014
- [X] T016 [US3] 运行 `zig build test -Ddemo-2d=true` 与 `zig build test -Dclear-only=true`，确认两个基础演示模式仍可独立构建与测试（src/main.zig、build.zig）

**Checkpoint**: All user stories should now be independently functional

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: 文档同步与全量回归验证

- [X] T017 [P] 在 README.md 的「操作与训练场」章节补充瞬间启停的确认结论，在「测试与验收」补充本特性的验证命令与结果（README.md）
- [X] T018 [P] 核对 specs/004-training-mode-controls/contracts/input-controls.md 与 specs/004-training-mode-controls/quickstart.md 与最终实现行为一致，修正措辞但不改变契约范围（specs/004-training-mode-controls/contracts/input-controls.md、specs/004-training-mode-controls/quickstart.md）
- [X] T019 运行完整验证：`zig build install test`、`zig build physics-test`、`zig build install test -Doptimize=ReleaseSafe` 及两种模式测试，全部退出码为 0（README.md、specs/004-training-mode-controls/quickstart.md）

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3+)**: All depend on Foundational phase completion
  - User stories can then proceed in parallel (if staffed)
  - Or sequentially in priority order (P1 → P2 → P3)
- **Polish (Phase 6)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational (Phase 2) - May integrate with US1 but should be independently testable
- **User Story 3 (P3)**: Can start after Foundational (Phase 2) - May integrate with US1/US2 but should be independently testable
- 所有故事共同依赖 T003/T004 提供的测试辅助，不互相依赖对方的实现

### Within Each User Story

- Tests MUST be written first and observed FAIL before implementation
- Tests (T005/T006、T009/T010、T013/T014) → implementation (T007、T011、T015) → verification (T008、T012、T016)
- Core implementation before integration; story complete before moving to next priority
- 严格遵守瞬间启停（FR-014），不引入加减速或平滑过渡

### Parallel Opportunities

- Setup: T001、T002 可并行
- Foundational: T003、T004 可并行（不同文件）
- 每个故事的两项测试任务可并行（T005+T006、T009+T010、T013+T014）
- 三个用户故事在 Foundational 完成后可由不同执行者并行推进
- Polish: T017、T018 可并行

---

## Parallel Example: User Story 1

```text
# 并行启动 US1 的两项测试（先失败）：
Task: "T005 [P] [US1] 视角映射与俯仰限幅测试 in src/engine/renderer/camera.zig"
Task: "T006 [P] [US1] 鼠标增量与捕获清零测试 in src/engine/platform/sdl/input.zig"

# 两项测试就绪后再执行：
Task: "T007 [US1] 收紧视角行为 in src/engine/renderer/camera.zig + src/engine/renderer/demo_scene.zig"
Task: "T008 [US1] 运行 zig build install test"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: Test User Story 1 independently（T008）
5. Deploy/demo if ready

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test independently → Deploy/Demo (MVP!)
3. Add User Story 2 → Test independently → Deploy/Demo
4. Add User Story 3 → Test independently → Deploy/Demo
5. Polish → 全量回归与 README 同步
6. Each story adds value without breaking previous stories

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together
2. Once Foundational is done:
   - Developer A: User Story 1
   - Developer B: User Story 2
   - Developer C: User Story 3
3. Stories complete and integrate independently

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Verify tests fail before implementing（宪章原则 II：Red-Green-Refactor）
- Commit after each task or logical group；提交前缀沿用 `feat:` / `docs:`，描述使用中文
- Stop at any checkpoint to validate story independently
- Avoid: vague tasks, same file conflicts, cross-story dependencies that break independence
- 数据模型约束引用均指向 data-model.md 的精确 `Entity.field`，不在本文件重复约束原文
