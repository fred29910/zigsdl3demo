# Feature Specification: 优化日志系统并支持编译期发布模式过滤 debug 日志

**Feature Branch**: `003-compile-time-log-level`

**Created**: 2026-11-26

**Status**: Draft

**Input**: User description: "分析当前项目情况，根据实际情况，优化当前项目日志系统，让其支持：在编译时通过--release参数让编译的内容只打印info+等级日志，否则可以打印debug日志"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 发布构建只输出 info 及以上日志 (Priority: P1)

作为发布构建的使用者，我以发布模式（`--release`）编译项目，希望编译产物只输出 info 及以上级别（info / warn / error）的日志，不输出 debug 级别日志，从而减少噪声并避免敏感或冗余细节进入正式产物。

**Why this priority**: 这是用户明确要求的核心能力，直接决定发布产物的日志噪声与可观测性边界。

**Independent Test**: 以 `--release` 编译并运行，触发各级别日志；检查输出中不存在 debug 级别条目，且 info / warn / error 条目仍正常输出。该测试不依赖非发布构建是否输出 debug。

**Acceptance Scenarios**:

1. **Given** 以发布模式（`--release`）编译的产物, **When** 代码产生 debug 级别日志, **Then** 该日志不被输出（不占用运行时输出，且不影响行为）。
2. **Given** 以发布模式（`--release`）编译的产物, **When** 代码产生 info / warn / error 级别日志, **Then** 这些日志正常输出。
3. **Given** 以发布模式（`--release`）编译的产物, **When** 尝试在运行时把最低级别调到低于 info, **Then** debug 级别日志仍不输出，有效最低级别不低于编译期设定的 info。

---

### User Story 2 - 非发布构建可打印 debug 日志 (Priority: P1)

作为开发者，我在不以发布模式编译（默认开发/调试构建）时，希望 debug 级别日志可以打印，从而便于排查问题。

**Why this priority**: 与 P1 的发布过滤相对应；否则 debug 能力在任何构建下都被压制，无法满足"否则可以打印 debug 日志"。

**Independent Test**: 不带 `--release` 编译并运行，触发一条 debug 级别日志；检查该条目被输出。该测试不依赖发布构建是否过滤 debug。

**Acceptance Scenarios**:

1. **Given** 非发布模式编译的产物, **When** 代码产生 debug 级别日志, **Then** 该日志被输出。
2. **Given** 非发布模式编译的产物, **When** 代码产生 info / warn / error 级别日志, **Then** 这些日志正常输出。

---

### User Story 3 - 现有日志行为不回归 (Priority: P2)

作为现有项目的维护者，我希望本次优化不改变当前已被验收的日志输出（级别集合、输出目的地、文本格式、模块标签），也不破坏现有构建模式与测试。

**Why this priority**: 本工程 M0–M11 已验收，增量改动不得破坏既有行为（宪法原则 II/III）。

**Independent Test**: 对比改动前后，已有 info / warn / error 日志的输出格式与目的地一致；原有测试在发布与非发布两种构建下均通过。

**Acceptance Scenarios**:

1. **Given** 现有代码未新增 debug 级别日志, **When** 以非发布或发布模式编译并运行, **Then** 现有 info / warn / error 输出与改动前一致。
2. **Given** 两种基础演示模式, **When** 以发布或非发布模式编译, **Then** 两种模式仍可独立构建与测试。

---

### Edge Cases

- 同时提供发布标志与显式优化级别时（如 `--release` 与 `-Doptimize=...`），只要最终构建为非调试（release）模式，即视为发布构建、仅输出 info 及以上。
- `--release` 带子模式时，无论具体 release 子模式，均视为发布构建、仅输出 info 及以上。
- 运行时请求把最低级别设为低于编译期下限时，有效最低级别不低于编译期下限（发布下不低于 info，非发布下不低于 debug）；运行时只能提高阈值、不能降低到编译期下限以下。
- 当前项目没有任何 debug 级别调用点；新增能力不得让现有 info / warn / error 调用点改变输出。
- 不受级别过滤的原始文本输出不得在发布构建下绕过级别过滤而输出低于 info 的内容。
- 过滤必须在编译期生效，不得依赖运行时环境变量、命令行参数或配置文件来启用/禁用 debug。

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: 系统 MUST 支持一个**编译期**开关：以发布模式编译（如 `--release`）时，仅输出 info 及以上级别（info / warn / error）日志；debug 级别日志被编译期过滤掉。
- **FR-002**: 在非发布（调试）模式编译时，系统 MUST 允许输出 debug 级别日志；编译期下限不高于 debug。
- **FR-003**: 编译期下限判定 MUST 只区分"发布"与"非发布"，不区分具体 release 子模式；任何非调试优化模式均视为发布。
- **FR-004**: 编译期过滤 MUST 在构建时确定，不得要求运行时环境变量、运行时参数或额外配置来启用；同一产物在运行时不能把 debug 级别日志在发布构建下重新打开。
- **FR-005**: 被编译期过滤掉的日志 MUST 不产生任何输出，且不得改变程序行为；被过滤日志的参数求值不得引入副作用或额外开销。
- **FR-006**: 系统 MUST 保留现有日志级别集合（debug / info / warn / error）及其相对顺序；info 及以上在两种构建下均可输出。
- **FR-007**: 系统 MUST 保留现有输出行为：写入标准错误、文本格式 `[LEVEL] module: message`、模块标签；不引入结构化/JSON 日志或新输出目的地。
- **FR-008**: 现有按级别过滤的能力 MUST 保留：运行时最低级别仍可调，但有效最低级别 MUST NOT 低于编译期下限（发布下不低于 info，非发布下不低于 debug）。
- **FR-009**: 不受级别过滤的原始文本输出路径 MUST NOT 在发布构建下输出低于 info 的内容，也不得绕过编译期级别过滤。
- **FR-010**: 改动 MUST NOT 破坏既有已验收行为与构建模式，包括两种基础演示模式；现有 info / warn / error 调用点输出 MUST NOT 改变。
- **FR-011**: 改动 MUST NOT 升级构建工具链、不放宽版本锁定、不破坏既有测试；发布与非发布两种构建均 MUST 通过既有测试。

### Key Entities

- **日志级别（LogLevel）**: 有序集合 debug < info < warn < error；级别决定消息是否输出，数值越高优先级越高。
- **编译期下限（Compile-time Minimum Level）**: 由构建是否为发布模式在编译期确定的最低输出级别；发布下为 info，非发布下为 debug。运行时过滤不得低于此下限。
- **日志消息（LogMessage）**: 一条待输出的记录，含级别、模块标签、已格式化文本；输出到标准错误。
- **构建模式（Build Mode）**: 发布（release，如 `--release`）或非发布（debug，默认）；决定编译期下限。

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 以发布模式编译并运行时，输出中 debug 级别条目数量为 0；info / warn / error 条目数量与改动前一致。
- **SC-002**: 以非发布模式编译并运行时，产生的 debug 级别条目被输出；info / warn / error 条目数量与改动前一致。
- **SC-003**: 同一份代码分别以发布与非发布模式编译后，行为差异仅限于"debug 级别日志是否输出"，无其它输出或行为差异。
- **SC-004**: 现有测试套件在发布与非发布两种构建下均 100% 通过；两种基础演示模式在两种构建下均可独立构建与测试。
- **SC-005**: 现有 info / warn / error 日志输出格式、目的地与模块标签与改动前完全一致（逐字节一致）。

## Assumptions

- `--release` 指构建工具的标准发布模式开关；发布模式 = 任何非调试优化模式；非发布 = 默认调试模式。当前项目已支持 `--release` 与显式优化级别，二者最终汇聚为同一"是否发布"判定。
- 编译期下限仅区分"发布 / 非发布"两档，不引入更细粒度的按模块或按级别构建配置（宪法原则 V：YAGNI）。
- 不改变输出目的地（标准错误）、文本格式与级别集合；不引入运行时环境变量或运行时参数来控制 debug。
- 现有调用点均为 info / warn / error；本特性不要求把现有调用点改为 debug，只要求让 debug 级别在非发布构建下**可**输出。
- 两种基础演示模式与现有测试构成回归基线；实现阶段需在发布与非发布两种构建下验证。
- 文档语言为中文；实现阶段同步更新 README 与验收记录，并遵循 Spec Kit 与宪法流程。
