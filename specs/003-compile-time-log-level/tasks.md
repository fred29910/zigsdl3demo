# Tasks: 优化日志系统并支持编译期发布模式过滤 debug 日志

**Input**: Design documents from `specs/003-compile-time-log-level/`

**Prerequisites**: `specs/003-compile-time-log-level/plan.md`, `specs/003-compile-time-log-level/spec.md`, `specs/003-compile-time-log-level/research.md`, `specs/003-compile-time-log-level/data-model.md`, `specs/003-compile-time-log-level/contracts/`, `.specify/memory/constitution.md`

**Tests**: 已按项目宪法 NON-NEGOTIABLE 原则启用：Red-Green-Refactor；测试先行并看到失败；实现最小改动；全绿后再 refactor。任务仍遵守 speckit 输出；不新增测试框架。

**Organization**: 按用户故事优先级组织；US1/US2 均 P1；US3 P2；Foundational 阻塞所有故事。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 可并行（不同文件，无未完成依赖）
- **[Story]**: `[US1]`, `[US2]`, `[US3]`；Setup/Foundational/Polish 无 story label
- 每个任务必须 `- [ ]` + 顺序 `Txxx` + 精确文件路径
- 引用数据约束时使用 `data-model.md` + `Entity.field`

## Path Conventions

单项目：`src/`, `build.zig`, `README.md`, `specs/003-compile-time-log-level/`。不新增 `tests/` 目录；单测放 `src/engine/core/logger.zig`。

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: 确认基线、版本、无回归前置；不创建新项目结构；不改依赖/生成物。

- [X] T001 Run `zig version` and baseline `zig build install test`; record exit status; no production changes yet; evidence path `specs/003-compile-time-log-level/quickstart.md`.
- [X] T002 Confirm no new dependency, no Zig upgrade, no shader/resource change in `build.zig.zon`, `build.zig`, `shaders/`, `src/engine/physics/`, `src/engine/assets/`, `src/engine/renderer/`, `zig-pkg/`, `zig-out/`, `.zig-cache/`.
- [X] T003 [P] Confirm no `before_tasks`/`after_tasks` hooks in `.specify/extensions.yml` and no hook changes in `.specify/extensions.yml`.

**Checkpoint**: Baseline known; proceed only if no unrelated pre-existing failure is introduced by this feature. If baseline fails, report exact command/output; do not patch unrelated code.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: 定义日志级别、构建模式、编译期下限、运行时收紧、输出契约；先建测试辅助行为；无用户故事可独立完成前必须完成。

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T004 Read `specs/003-compile-time-log-level/contracts/logging-contract.md` and map every requirement in `specs/003-compile-time-log-level/spec.md`; keep `src/root.zig` `pub const Logger` compatibility in `src/root.zig`.
- [X] T005 Preserve canonical log model from `specs/003-compile-time-log-level/data-model.md`: `LogLevel.debug`, `LogLevel.info`, `LogLevel.warn`, `LogLevel.error_`, `LogLevel.ordering`, `LogLevel.canonical_names`, `LogLevel.validation`, `LogMessage.level`, `LogMessage.module`, `LogMessage.formatted_text`, `LogMessage.stderr`, `LogMessage.format`, `LogMessage.filtered_debug`, `LogMessage.no_persistence`, `CompileTimeDebugCall.rule`, `CompileTimeDebugCall.guard`, `CompileTimeDebugCall.rejected`; implement/verify in `src/engine/core/logger.zig`.
- [X] T006 Implement compile-time build model from `specs/003-compile-time-log-level/data-model.md`: `BuildMode.mode`, `BuildMode.release_mode`, `BuildMode.source`, `BuildMode.output`, `BuildMode.validation`, `CompileTimeMinimumLevel.compile_time_min_level`, `CompileTimeMinimumLevel.release_mode`, `CompileTimeMinimumLevel.lifecycle`, `CompileTimeMinimumLevel.scope`, `RuntimeMinimumLevel.level`, `RuntimeMinimumLevel.effective_min_level`, `RuntimeMinimumLevel.rule`, `RuntimeMinimumLevel.compatibility`; implement/verify `release_mode`, `compile_time_min_level`, `enabledComptime`, `effectiveMinLevel`, `enabled` in `src/engine/core/logger.zig`.
- [X] T007 Preserve constructor/format API in `src/engine/core/logger.zig`: `Logger.init`, `Logger.enabled`, `Logger.format`, `Logger.log`, `levelName`; keep `Logger.level` default not lower than `CompileTimeMinimumLevel.compile_time_min_level`; do not change existing call sites in `src/main.zig`, `src/engine/assets/`, `src/engine/renderer/`.
- [X] T008 TDD RED: add pure unit tests for `Level` ordering, `levelName`, `effectiveMinLevel(compile_time_min_level, runtime_level)`, `enabledComptime`, and runtime clamping in `src/engine/core/logger.zig`; run `zig test src/engine/core/logger.zig`; verify tests fail for missing implementation; obtain user confirmation of test intent before implementation.
- [X] T009 TDD GREEN/REFACTOR: implement minimal pure helpers in `src/engine/core/logger.zig`; run `zig test src/engine/core/logger.zig`; verify green; refactor only after green.
- [X] T010 Preserve `build.zig` existing `std.builtin.Optimize` handling and version check in `build.zig`; no `-Dlog-level`, no logging env, no new `-D...` requirement; `release_mode` in `src/engine/core/logger.zig` keyed on `@import("builtin").mode`, not on `std_options`, env, or runtime args.
- [X] T011 Support bare `zig build --release` on Zig `0.17.1` in `build.zig` with this exact precedence: explicit `-Doptimize=...` wins; otherwise `--release=<mode>` maps to that mode; otherwise bare `--release` maps to `.ReleaseSafe`; otherwise `.Debug`. Preserve `-Doptimize=Debug`, `-Doptimize=debug`, `-Doptimize=ReleaseSafe/ReleaseFast/ReleaseSmall`, `--release=fast/safe/small`; no `build.zig.zon` edits.
- [X] T012 Add build-mode contract checks from `specs/003-compile-time-log-level/quickstart.md`: `zig build install test`, `zig build install test --release`, `zig build install test --release=safe`, `zig build install test -Doptimize=ReleaseSafe`, `zig build test -Ddemo-2d=true`, `zig build test -Dclear-only=true`, `zig build test -Ddemo-2d=true --release`, `zig build test -Dclear-only=true --release`; record exit statuses; do not claim pass before running.

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel.

---

## Phase 3: User Story 1 - 发布构建只输出 info 及以上日志 (Priority: P1) 🎯 MVP

**Goal**: `--release` 产物仅输出 info+；debug 不输出、不改行为、不额外开销；运行时不能重开 debug。

**Independent Test**: `zig build install test --release` + focused logger test；触发 `.debug/.info/.warn/.error_`；release 输出 `[DEBUG]` count = 0；info/warn/error 与改动前一致；runtime `Logger.init(.debug)` cannot lower `effective_min_level` below `info`；no unfiltered raw output below info.

**Contract**: `specs/003-compile-time-log-level/contracts/logging-contract.md` release / effective-level / output / `Logger.print` sections; FR-001/FR-003/FR-004/FR-005/FR-006/FR-007/FR-008/FR-009/SC-001/SC-003/SC-004/SC-005.

### Tests for User Story 1 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T013 [P] [US1] TDD RED: test release `CompileTimeMinimumLevel.compile_time_min_level == .info`, `LogLevel.debug` filtered, `LogLevel.info/warn/error_` allowed, and no runtime lowering below `.info` in `src/engine/core/logger.zig`; verify `zig test src/engine/core/logger.zig` fails before implementation; obtain user confirmation.
- [X] T014 [P] [US1] TDD RED: test release bare `zig build --release`, `zig build --release=safe/fast/small`, `-Doptimize=ReleaseSafe`, and `-Doptimize=ReleaseFast/ReleaseSmall` produce non-Debug and info+ only using `specs/003-compile-time-log-level/quickstart.md`; verify current `zig build --release` failure is captured; no implementation yet.
- [X] T015 [P] [US1] TDD RED: test filtered `.debug` has no output, no formatting, no new sink; test that caller-owned expensive/side-effecting args are not evaluated when guarded by `Logger.enabledComptime(.debug)`; `LogMessage.filtered_debug`, `CompileTimeDebugCall.rule`, `CompileTimeDebugCall.guard`, `CompileTimeDebugCall.rejected` in `specs/003-compile-time-log-level/data-model.md`; `src/engine/core/logger.zig`; verify failure before implementation.
- [X] T016 [P] [US1] TDD RED: test `Logger.print`/raw `std.debug.print` cannot emit below `LogMessage.format` info in release; `LogMessage.stderr`, `LogMessage.format`, `CompileTimeDebugCall.rejected` in `specs/003-compile-time-log-level/data-model.md`; `src/engine/core/logger.zig`; verify failure before implementation.

### Implementation for User Story 1

- [X] T017 [US1] TDD GREEN: implement release comptime `.debug` drop + `effective_min_level >= .info` in `src/engine/core/logger.zig`; minimal code; run focused tests; verify green.
- [X] T018 [US1] TDD GREEN: implement `Logger.enabledComptime(.debug)` guard and document caller pure/guard rule in `src/engine/core/logger.zig` + `specs/003-compile-time-log-level/contracts/logging-contract.md`; `CompileTimeDebugCall.guard` in `specs/003-compile-time-log-level/data-model.md`.
- [X] T019 [US1] TDD GREEN: remove or disable unfiltered `Logger.print` raw output in release; ensure `Logger.log` `std.debug.print` only after comptime filtering in `src/engine/core/logger.zig`; no output-format change.
- [X] T020 [US1] TDD GREEN: implement `build.zig` release selection from T011; run `zig build install test --release`; verify no missing-preferred-optimization error; no dependency changes.
- [X] T021 [US1] REFACTOR: clean up helpers/naming only after green in `src/engine/core/logger.zig` + `build.zig`; rerun focused + `zig build install test --release`.
- [X] T022 [US1] Run US1 independent test + `zig build install test --release`; verify `[DEBUG]` count = 0; verify info/warn/error unchanged; record evidence in `specs/003-compile-time-log-level/quickstart.md` or final report; no claim before run.

**Checkpoint**: User Story 1 should be fully functional and testable independently. MVP scope = Setup + Foundational + US1.

---

## Phase 4: User Story 2 - 非发布构建可打印 debug 日志 (Priority: P1)

**Goal**: 非发布构建 debug 可打印；`Logger.init(.debug)` 非 release 可输出；`.info` runtime 仍可收紧；与 US1 仅差 debug 是否输出。

**Independent Test**: `zig build install test` + focused logger test；触发 `.debug`；非 release `[DEBUG]` count >= 1；info/warn/error 与改动前一致；release 对照 `[DEBUG]` count = 0.

**Contract**: `specs/003-compile-time-log-level/contracts/logging-contract.md` non-release effective-level + `Logger.init`; FR-002/FR-004/FR-005/FR-006/FR-007/FR-008/SC-002/SC-003.

### Tests for User Story 2 ⚠️

- [X] T023 [P] [US2] TDD RED: test non-release `CompileTimeMinimumLevel.compile_time_min_level == .debug`, `.debug` allowed, `Logger.init(.debug)` emits, `RuntimeMinimumLevel.level` can raise to `.info`, runtime cannot lower below `.debug` in `specs/003-compile-time-log-level/data-model.md` `RuntimeMinimumLevel.compatibility`; `src/engine/core/logger.zig`; verify failure before implementation; obtain user confirmation.
- [X] T024 [P] [US2] TDD RED: test non-release `.debug` uses existing `[DEBUG] ...` `LogMessage.format`, `LogMessage.stderr`, `LogMessage.filtered_debug` in `specs/003-compile-time-log-level/data-model.md`; no new output sink; `src/engine/core/logger.zig`; verify failure before implementation.
- [X] T025 [P] [US2] TDD RED: test filtered/non-filtered comparison proves only `.debug` output differs between release and non-release for same input in `src/engine/core/logger.zig` + `specs/003-compile-time-log-level/quickstart.md`; verify failure before implementation.

### Implementation for User Story 2

- [X] T026 [US2] TDD GREEN: implement non-release `.debug` floor `.debug` + existing runtime raise in `src/engine/core/logger.zig`; no change to existing `.info` call sites; run focused tests; verify green.
- [X] T027 [US2] Ensure `Logger.init(.info)` still suppresses `.debug` in non-release and `Logger.init(.debug)` does not bypass release floor in `src/engine/core/logger.zig`; `RuntimeMinimumLevel.level`, `RuntimeMinimumLevel.effective_min_level`, `RuntimeMinimumLevel.rule`, `RuntimeMinimumLevel.compatibility` in `specs/003-compile-time-log-level/data-model.md`.
- [X] T028 [US2] Run US2 independent test + `zig build install test`; verify non-release `[DEBUG]` count >= 1 on a logger whose effective minimum permits debug (e.g. `Logger.init(.debug)`), that `Logger.init(.info)` still suppresses debug, and info/warn/error unchanged; release control `zig build install test --release` `[DEBUG]` count = 0; record evidence in `specs/003-compile-time-log-level/quickstart.md`.

**Checkpoint**: User Stories 1 AND 2 should both work independently.

---

## Phase 5: User Story 3 - 现有日志行为不回归 (Priority: P2)

**Goal**: 增量改动；不改现有 info/warn/error；不破坏输出格式/目的地/模块；不破坏两种基础演示模式；测试 release + non-release。

**Independent Test**: before/after 现有日志 `stderr` byte-identical；`zig build install test` + `zig build install test --release`；two basic modes both modes；no source regression.

**Contract**: `specs/003-compile-time-log-level/contracts/logging-contract.md` compatibility + verification; FR-006/FR-007/FR-010/FR-011/SC-004/SC-005; constitution I-V.

### Tests for User Story 3 ⚠️

- [X] T029 [P] [US3] TDD RED: test existing `test "logger level filtering"`, `test "logger format"`, `[INFO] core: hello 42\n`, `.info/.warn/.error_`, `Logger.init(.info)`, `Logger.level`, `LogMessage.format`, `LogMessage.stderr`, `LogLevel.ordering` remain compatible in `src/engine/core/logger.zig`; verify failure/no regression criteria before implementation.
- [X] T030 [P] [US3] Add byte-level regression capture for existing info/warn/error output before/after in `specs/003-compile-time-log-level/quickstart.md`; compare stderr exactly; no change to `src/main.zig`, `src/engine/assets/`, `src/engine/renderer/`.
- [X] T031 [P] [US3] Add no-regression build checks for `-Ddemo-2d=true`, `-Dclear-only=true`, `-Doptimize=ReleaseSafe`, `--release`, no Jolt/assets/ImGui/audio introduction in `build.zig` + `specs/003-compile-time-log-level/quickstart.md`; no `build.zig.zon` edits.

### Implementation for User Story 3

- [X] T032 [US3] Run `zig build install test` and `zig build install test --release`; verify all existing tests pass; no output changes; record in `specs/003-compile-time-log-level/quickstart.md`.
- [X] T033 [US3] Run `zig build test -Ddemo-2d=true`, `zig build test -Dclear-only=true`, `zig build test -Ddemo-2d=true --release`, `zig build test -Dclear-only=true --release`; verify both modes independently build/test; no new dependencies; record in `specs/003-compile-time-log-level/quickstart.md`.
- [X] T034 [US3] If logging touches physics/collision/character/weapon (expected no), run `zig build physics-test`; otherwise record not required; no physics parameter changes in `src/engine/physics/`.
- [X] T035 [US3] Verify no edits to `build.zig.zon`, `shaders/`, `zig-pkg/`, `zig-out/`, `.zig-cache/`, `.opencode/commands/`, `.specify/templates/`, `.specify/scripts/`; no shader revalidation needed; `git status --short` evidence.
- [X] T036 [US3] Run quickstart smoke references from `specs/003-compile-time-log-level/quickstart.md` where available; record not run real GPU physical device / physical audio; Linux virtual display + Mesa Lavapipe baseline only; no claim real GPU WM/audio verified.

**Checkpoint**: All user stories independently functional; no regression.

---

## Phase N: Polish & Cross-Cutting Concerns

**Purpose**: docs, cleanup, full verification matrix, honesty.

- [X] T037 [P] Update `README.md` logging/build/test/acceptance sections: `zig build --release`, non-release debug, release info+, no runtime flag, output unchanged; Chinese docs; no implementation-detail claims until verified.
- [X] T038 [P] Update `docs/` records if required by `AGENTS.md`; no shader/M11 physical claims; document known Zig 0.17.1 `--release=fast/safe/small` behavior if still relevant in `README.md`.
- [X] T039 Run `zig fmt --check src/engine/core/logger.zig src/root.zig build.zig`; no generated files.
- [X] T040 Run full `zig build install test` + `zig build install test --release` at settled state; run `zig build install test -Doptimize=ReleaseSafe` per repo acceptance; record exact commands/exit statuses/log evidence in `specs/003-compile-time-log-level/quickstart.md`.
- [X] T041 Re-run two basic modes at settled state: `zig build test -Ddemo-2d=true`, `zig build test -Dclear-only=true`, `zig build test -Ddemo-2d=true --release`, `zig build test -Dclear-only=true --release`; record exit statuses in `specs/003-compile-time-log-level/quickstart.md`.
- [X] T042 Re-run `specs/003-compile-time-log-level/quickstart.md` validation; verify `[DEBUG]` release count = 0, non-release debug available, byte-identical info/warn/error; list any failures by name; do not omit red tests.
- [X] T043 Run `/speckit.converge` readiness check / fresh review per `specs/003-compile-time-log-level/plan.md`; verify spec coverage, no unresolved clarifications, no generated-file edits; no claim complete before verification.
- [X] T044 Commit atomic `feat:` + Chinese message only after tests pass; do not commit `.zig-cache`, `zig-out`, `zig-pkg`, generated artifacts; no `docs/superpowers` plan for this feature（user/ speckit path overrides).
- [X] T045 Produce honest final report: implemented files, tests run exact commands/exit statuses/log evidence, tests not run, real GPU/physical audio not verified, remaining limits; reference `specs/003-compile-time-log-level/quickstart.md`.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies; start immediately.
- **Foundational (Phase 2)**: Depends on Phase 1; **BLOCKS all user stories**.
- **User Stories (Phase 3+)**: All depend on Phase 2 complete.
  - US1 and US2 are both P1; after Foundational can proceed in parallel if staffed, but both write `src/engine/core/logger.zig` + `build.zig` in US1; avoid concurrent same-file edits unless worktree/lock used.
  - Sequential order recommended P1 US1 → P1 US2 → P2 US3.
- **Polish (Final Phase)**: Depends on all desired user stories complete; run once at settled state.

### User Story Dependencies

- **User Story 1 (P1)**: After Foundational; no dependency on US2/US3; implements release floor + `--release` + no filtered debug.
- **User Story 2 (P1)**: After Foundational; can validate after US1 but independently testable; implements non-release debug + runtime clamp; no dependency on US3.
- **User Story 3 (P2)**: After Foundational; regression against US1/US2 outputs; independent test after no-regression baseline.

### Within Each Story

- Tests (if included) MUST be written and FAIL before implementation.
- Get user confirmation of test intent before production implementation per constitution.
- Pure helpers before call-site changes.
- Core `Logger` before `build.zig` release selection where dependency exists.
- `build.zig` release selection independent of `Logger` runtime format but verified with US1.
- Docs after verified behavior.
- Story complete before moving to next priority.

### Parallel Opportunities

- **Phase 1**: T003 can run in parallel with T001/T002 if no writes.
- **Phase 2**: T004/T005/T006/T007 analysis can be parallel; T008 must precede T009; T010/T011 analysis can be parallel; T012 after T011.
- **US1**: T013/T014/T015/T016 test authoring can be parallel if separate temporary test harnesses; implementation T017/T018/T019/T020 sequential where same files; avoid concurrent writes.
- **US2**: T023/T024/T025 can be parallel test authoring; T026/T027 sequential; T028 after.
- **US3**: T029/T030/T031 can be parallel; T032/T033/T034/T035/T036 verification can run after implementation; avoid concurrent git/build cache conflicts unless separate caches.
- **Polish**: T037/T038 docs can be parallel; tests after settled state; no `[P]` on tasks that write same file or need prior outputs.

### Parallel Example: User Story 1

```bash
# Launch US1 tests together if using separate agents/worktrees:
# T013 release floor test in src/engine/core/logger.zig
# T014 build-mode contract in specs/003-compile-time-log-level/quickstart.md
# T015 filtered-debug no-overhead test in src/engine/core/logger.zig
# T016 no-raw-bypass test in src/engine/core/logger.zig
# Avoid parallel writes to same file unless using disjoint patches.
```

### Parallel Example: User Story 2

```bash
# Launch US2 tests together:
# T023 non-release floor test
# T024 debug output format test
# T025 release-vs-nonrelease diff test
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup.
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories).
3. Complete Phase 3: User Story 1 release info+ + `--release`.
4. **STOP and VALIDATE**: `zig build install test --release`; `[DEBUG]` release count = 0; info/warn/error unchanged.
5. Deploy/demo if ready; no claim before evidence.

### Incremental Delivery

1. Setup + Foundational → foundation ready.
2. US1 → test independently → MVP.
3. US2 → test independently → non-release debug.
4. US3 → full no-regression matrix → Polish.
5. Each story adds value without breaking previous stories.

### Parallel Team Strategy

1. Team completes Phase 1 + Phase 2 together.
2. Once Foundational done:
   - Developer A: US1 release filtering + `build.zig` release selection.
   - Developer B: US2 non-release debug + runtime clamp.
   - Developer C: US3 regression tests + docs prep.
3. Reconcile all writers; run Polish once at settled state.
4. Avoid same-file concurrent writes; prefer disjoint patches/worktrees; no claims without verification.

---

## Data-model constrained-field citation audit

Every canonical `Entity.field` in `specs/003-compile-time-log-level/data-model.md` `## Field-level constraints` has at least one implementing/verification task:

- `LogLevel.*`, `LogMessage.*`, `CompileTimeDebugCall.*`: T005/T007/T013/T015/T016/T017/T018/T019/T022/T023/T024/T026/T027/T029.
- `BuildMode.*`, `CompileTimeMinimumLevel.*`, `RuntimeMinimumLevel.*`: T006/T010/T011/T013/T014/T017/T020/T023/T026/T027/T028/T029.
- BuildMode `ReleaseSafe/ReleaseFast/ReleaseSmall`, `debug/safe/fast/small`, `--release`, `-Doptimize`, `-Ddemo-2d`, `-Dclear-only`: T011/T012/T014/T020/T031/T033.
- Output `stderr`, `[LEVEL] module: message\n`, `[DEBUG]/[INFO]/[WARN]/[ERROR]`: T005/T007/T019/T022/T024/T028/T029/T030/T042.

## Notes

- [P] tasks = different files, no dependencies.
- [Story] label maps task to specific user story; Setup/Foundational/Polish no story label.
- Every task has checkbox + ID + exact file path; no sample tasks.
- No new dependencies; no `std.log` migration; no runtime env/args; no output format change; no generated-file edits.
- Filtered `.debug` no arg eval requires pure args or `Logger.enabledComptime(.debug)` guard; no masking side effects.
- Full tests must pass at settled state; no completion claims without exact evidence.
