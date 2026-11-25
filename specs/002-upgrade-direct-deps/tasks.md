---

description: "Tasks for upgrading direct dependencies to latest compatible versions"
---

# Tasks: 升级直接依赖至最新版本

**Input**: Design documents from `/specs/002-upgrade-direct-deps/`

**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: 依据宪章 II 的 Red-Green-Refactor，先编写「目标版本检查」并确认其在升级前失败（T011/T012），获得用户确认后才允许执行升级（T013 起）；GREEN 阶段由既有门禁 G1–G6 判定（FR-007/FR-008）。不新增与产品行为相关的测试文件。

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Single project**: `build.zig.zon`、`build.zig`、`README.md`、`src/` 位于仓库根
- 设计文档位于 `specs/002-upgrade-direct-deps/`
- 禁止编辑 `zig-pkg/`、`zig-out/`、`.zig-cache/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: 建立可回退的升级基线与门禁基线

- [X] T001 运行 `zig version` 与 `git status`，确认 Zig 精确为 0.17.1 且工作树干净；将 `build.zig.zon` 中每项依赖的 `当前版本标识` 与 `当前内容哈希` 快照写入 `specs/002-upgrade-direct-deps/research.md` R1 表格（依据 data-model.md `直接依赖.当前版本标识`、`直接依赖.当前内容哈希`）
- [X] T002 [P] 按 `specs/002-upgrade-direct-deps/contracts/acceptance-gates.md` 执行基线 G1–G5，记录 `验收门禁.名称`、`验收门禁.命令` 与 `验收门禁.结果` 到 `specs/002-upgrade-direct-deps/quickstart.md` 的「基线」小节（依据 data-model.md `验收门禁.名称`、`验收门禁.命令`、`验收门禁.结果`）

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: 在任一用户故事开始前固定门禁、回退规则与记录结构

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T003 [P] 在 `specs/002-upgrade-direct-deps/contracts/acceptance-gates.md` 固定 G1–G6 的命令、范围与「失败即回退」判定规则，确认没有可跳过的门禁（依据 data-model.md `验收门禁.命令`、`验收门禁.范围`）
- [X] T004 [P] 核对 `specs/002-upgrade-direct-deps/data-model.md` 的实体字段与校验规则，确认 `直接依赖.名称`、`直接依赖.来源类型`、`直接依赖.兼容性判定`、`直接依赖.最终结论` 将覆盖全部 6 项直接依赖
- [X] T005 [P] 用当前已锁定 URL 验证 `zig fetch <url>` 可复现 `直接依赖.当前内容哈希`，确认哈希来源可信（依据 data-model.md `直接依赖.当前内容哈希`；契约见 `specs/002-upgrade-direct-deps/contracts/dependency-manifest.md`）
- [X] T006 [P] 在 `README.md`「技术栈与依赖」章节建立升级记录表骨架，列包含 `升级记录.依赖名称`、`升级记录.原版本`、`升级记录.新版本`、`升级记录.理由`（依据 data-model.md 对应字段）

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - 盘点直接依赖并识别可升级项 (Priority: P1) 🎯 MVP

**Goal**: 产出覆盖全部直接依赖的清单，每项都有当前版本、上游最新版本、兼容性判定与升级/保持结论，且不改动任何依赖。

**Independent Test**: 仅完成本阶段即可核对 `specs/002-upgrade-direct-deps/research.md` R1 表格：6 个依赖键与 `build.zig.zon` 完全一致，每项均有明确结论，`build.zig.zon` 未发生任何改动（满足 SC-001）。

### Implementation for User Story 1

- [X] T007 [US1] 枚举 `build.zig.zon` `.dependencies` 的全部 6 个键，将 `直接依赖.名称`、`直接依赖.来源类型`、`直接依赖.当前版本标识`、`直接依赖.当前内容哈希` 写入 `specs/002-upgrade-direct-deps/research.md` R1（依据 data-model.md 对应字段）
- [X] T008 [US1] 通过 GitHub API 查询每项上游最新版本并记录 `直接依赖.上游最新版本` 与查询日期/来源到 `specs/002-upgrade-direct-deps/research.md` R1（依据 data-model.md `直接依赖.上游最新版本`）
- [X] T009 [US1] 在 `specs/002-upgrade-direct-deps/research.md` R2–R5 记录每项 `直接依赖.兼容性判定` 与 `直接依赖.最终结论`，含保持原样的理由（依据 data-model.md 对应字段；FR-002/FR-006）
- [X] T010 [US1] 校验清单键集合与 `build.zig.zon` 完全一致（覆盖率 100%，SC-001），在 `specs/002-upgrade-direct-deps/research.md` R1 补记核对结论

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently

---

## Phase 4: User Story 2 - 将兼容的直接依赖升级至最新版本 (Priority: P1)

**Goal**: 将 3 项存在兼容更新的依赖逐项升级到精确最新版本与固定哈希；不兼容者保持原样。

**Independent Test**: 每项升级后立即运行对应门禁；全部候选升级落地后 `build.zig.zon` 中浮动引用数为 0、lazy 标记与工具链版本未变（满足 SC-002/SC-005）。

### RED — 先写检查并看到失败（宪章 II）

- [X] T011 [US2] 编写目标版本检查脚本 `specs/002-upgrade-direct-deps/contracts/check-target-versions.sh`：断言 `build.zig.zon` 中 imgui 为 v1.93.0、jolt 为 v5.7.0、stb 为提交 `6b5799b`，且所有 `.url` 为不可变引用、`.hash` 非空、`lazy` 与 `minimum_zig_version = "0.17.1"` 未变（依据 data-model.md `直接依赖.来源类型`、`直接依赖.当前内容哈希`）。**本任务在升级前完成，不得同时修改 `build.zig.zon`**
- [ ] T012 [US2] 运行 `specs/002-upgrade-direct-deps/contracts/check-target-versions.sh`，确认在当前版本下检查**失败（RED）**；将失败输出与用户确认记录到 `specs/002-upgrade-direct-deps/contracts/acceptance-gates.md`。**未获得用户确认前不得开始 T013**

### GREEN — 逐项升级并通过门禁

> 三项升级均改写同一文件 `build.zig.zon`，因此不可并行，须按 T013 → T015 → T017 顺序执行。

- [ ] T013 [US2] 用 `zig fetch <v1.93.0 URL>` 取得哈希，将 `imgui` 的 `.url` 与 `.hash` 更新到 v1.93.0 于 `build.zig.zon`，保持 `lazy = true`（依据 data-model.md `直接依赖.来源类型`、`直接依赖.当前内容哈希`；契约见 `specs/002-upgrade-direct-deps/contracts/dependency-manifest.md`）
- [ ] T014 [US2] 在 imgui 升级后执行 G1、G2、G4、G5，将 `验收门禁.结果` 记录到 `specs/002-upgrade-direct-deps/contracts/acceptance-gates.md`；任一失败时按 FR-011 先做为采用 v1.93.0 所必需的最小源码适配并复测，仍不满足时才回退 imgui 至 v1.92.5 并重跑（依据 data-model.md `验收门禁.命令`、`验收门禁.结果`）
- [ ] T015 [US2] 用 `zig fetch <v5.7.0 URL>` 取得哈希，将 `jolt` 的 `.url` 与 `.hash` 更新到 v5.7.0 于 `build.zig.zon`，保持 `lazy = true`（依据 data-model.md `直接依赖.来源类型`、`直接依赖.当前内容哈希`）
- [ ] T016 [US2] 在 jolt 升级后执行 G1、G2、G3，将 `验收门禁.结果` 记录到 `specs/002-upgrade-direct-deps/contracts/acceptance-gates.md`；任一失败（尤其 C ABI 桥接或物理不变量）时按 FR-011 先做必要的最小源码适配并复测，仍不满足时才回退 jolt 至 v5.5.0 并重跑（依据 data-model.md `验收门禁.命令`、`验收门禁.结果`）
- [ ] T017 [US2] 用 `zig fetch <commit 6b5799b URL>` 取得哈希，将 `stb` 的 `.url` 与 `.hash` 更新到 `6b5799b` 于 `build.zig.zon`，保持 `lazy = true`（依据 data-model.md `直接依赖.来源类型`、`直接依赖.当前内容哈希`）
- [ ] T018 [US2] 在 stb 升级后执行 G1、G2，将 `验收门禁.结果` 记录到 `specs/002-upgrade-direct-deps/contracts/acceptance-gates.md`；失败时按 FR-011 先做必要的最小源码适配并复测，仍不满足时才回退 stb 至 `f056911` 并重跑（依据 data-model.md `验收门禁.命令`、`验收门禁.结果`）
- [ ] T019 [US2] 重新运行 `specs/002-upgrade-direct-deps/contracts/check-target-versions.sh`，确认全部检查通过（GREEN）；并检查 `build.zig.zon`：6 个键不变、所有 `.url` 为不可变 tag/提交、所有 `.hash` 非空、`lazy` 标记与 `minimum_zig_version = "0.17.1"` 未变（依据 data-model.md `直接依赖.来源类型`、`直接依赖.当前内容哈希`）

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently

---

## Phase 5: User Story 3 - 验证升级后无回归并留痕 (Priority: P2)

**Goal**: 全量验证升级结果、离线干净构建，并在 README 留下每项依赖的可追溯升级记录。

**Independent Test**: 在最终状态下，G1–G6 全部通过且 README 中 6 项依赖均有「原版本 → 新版本/保持原样 + 理由」（满足 SC-003/SC-004/SC-006）。

### Implementation for User Story 3

- [ ] T020 [US3] 在最终依赖状态下执行完整 G1–G5，将 `验收门禁.结果` 汇总写入 `specs/002-upgrade-direct-deps/contracts/acceptance-gates.md`（依据 data-model.md `验收门禁.命令`、`验收门禁.结果`）
- [ ] T021 [US3] 清理本地依赖缓存后断网执行 G6 离线干净构建，将 `验收门禁.结果` 写入 `specs/002-upgrade-direct-deps/contracts/acceptance-gates.md`；失败则定位依赖并回退后重跑（依据 data-model.md `验收门禁.结果`）
- [ ] T022 [US3] 填充 `README.md`「技术栈与依赖」升级记录表：6 项依赖逐条写入 `升级记录.依赖名称`、`升级记录.原版本`、`升级记录.新版本`、`升级记录.理由`（依据 data-model.md 对应字段）
- [ ] T023 [US3] 核对 `README.md` 与 `build.zig`：glTF 支持边界、物理步长 1/60s / 每帧 6 步 / 相机 1.6m / 最近碰撞射线、缓存命中 `embedded:demo.glb`、SPIR-V 与 HLSL 同步均未改变（FR-010）
- [ ] T024 [P] [US3] 按 `specs/002-upgrade-direct-deps/quickstart.md` 复核步骤与最终状态一致，更新其中与实测不符的命令或预期

**Checkpoint**: All user stories should now be independently functional

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: 最终一致性检查、提交与端到端验收

- [ ] T025 [P] 检查 `README.md`「常见问题」是否需补充升级后的构建/依赖说明
- [ ] T026 审阅完整 diff：确认仅 `build.zig.zon`、`specs/002-upgrade-direct-deps/contracts/check-target-versions.sh` 与设计/验收文档被修改，`src/`、`shaders/`、`assets/` 无改动
- [ ] T027 按宪章以原子提交落地，使用 `feat:` / `docs:` 前缀与中文描述，提交前删除 `.specify/memory/constitution.md` 中遗留的临时 Sync Impact Report 审阅材料（如适用）
- [ ] T028 按 `specs/002-upgrade-direct-deps/quickstart.md` 执行一次端到端验证，确认 SC-001～SC-006 全部满足

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3+)**: All depend on Foundational phase completion
  - US1 与 US2 同为 P1；US2 依赖 US1 的盘点结论作为升级候选依据
  - US2 内部必须先完成 RED（T011/T012）并获用户确认，才允许进入 GREEN（T013 起）
  - US3 依赖 US1 与 US2 的最终状态
- **Polish (Final Phase)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P1)**: Depends on US1 inventory；RED 阶段（T011/T012）先于 GREEN 阶段（T013–T019）；三项升级彼此顺序依赖（同一文件 `build.zig.zon`）
- **User Story 3 (P2)**: Depends on US1 + US2 final state

### Within Each User Story

- US1：先枚举/查询，再判定兼容性，最后核对覆盖率
- US2：**先写检查并看到失败（RED）、获得用户确认**，再逐项升级 → 即时门禁 → 失败回退 → 最后确认检查通过（GREEN）
- US3：先全量门禁与离线构建，再写 README 记录，最后核对不变量
- 任何门禁失败都必须回退，不得降低验收标准

### Parallel Opportunities

- T002 与 T001 可并行（分别写入 `quickstart.md` 与 `research.md`）
- Phase 2 中 T003、T004、T005、T006 可并行（不同文件）
- T024 与 T025 可并行（不同文件）
- US2 的 RED 阶段 T011 与 T012 必须串行（先写检查，再运行看失败）
- US2 的 GREEN 阶段不可并行：T013/T015/T017 均改写 `build.zig.zon`
- US1 内部不可并行：T007–T010 均围绕 `research.md` 同一表格

---

## Parallel Example: User Story 1

```bash
# 盘点阶段按依赖顺序串行更新 research.md R1 表格：
Task: "T007 枚举 build.zig.zon 的 6 个直接依赖并写入 research.md"
Task: "T008 查询上游最新版本并写入 research.md R1"
Task: "T009 记录兼容性判定与最终结论到 research.md R2–R5"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: 核对 research.md 的 6 项依赖盘点与结论，确认 `build.zig.zon` 未改动
5. 此 MVP 仅提供可评审的升级决策清单；用户可见的升级价值在 US2 才交付

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → 评审升级决策清单（MVP!）
3. Add User Story 2 → RED（写检查、看失败、确认）后逐项升级并门禁验证
4. Add User Story 3 → 全量验证 + 离线构建 + README 留痕
5. Each story adds value without breaking previous stories

### Parallel Team Strategy

本功能并行度有限：US2 的 RED 阶段串行，GREEN 阶段三项升级均改写 `build.zig.zon` 必须串行。可并行部分为 Setup/Foundational 的文档任务与最终 polish 任务。

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Avoid: vague tasks, same file conflicts, cross-story dependencies that break independence
