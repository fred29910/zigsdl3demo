# Research: 升级直接依赖至最新版本

**日期**：2026-11-25
**方法**：GitHub REST API（`releases/latest`、`commits`）查询上游版本；结合 `build.zig.zon` 现状与项目宪章判定兼容性。调研允许联网，升级完成后必须离线可构建。

## R1 — 每项直接依赖的最新版本是什么？

**Decision**：

| 依赖 | 当前锁定 | 上游最新 | 结论 |
| --- | --- | --- | --- |
| Jolt Physics (`jolt`) | v5.5.0 | **v5.7.0**（2026-11-14） | 候选升级 |
| Dear ImGui (`imgui`) | v1.92.5 | **v1.93.0**（2026-10-14） | 候选升级 |
| stb (`stb`) | 提交 `f056911` | **master HEAD `6b5799b`**（2026-11-19） | 候选升级 |
| cgltf (`cgltf`) | v1.15 | v1.15（2025-02-09） | 保持原样（已是最新） |
| miniaudio (`miniaudio`) | 0.11.26 | 0.11.26（2026-10-31） | 保持原样（已是最新） |
| sdl3-zig (`sdl3`) | 提交 `aaa5868` | `aaa5868`（2026-11-24，main 最新） | 保持原样（已是最新） |

**升级前基线快照（T001，2026-11-25；Zig 0.17.1，源码与依赖声明无未提交改动）**：

| 依赖 | 名称 | 来源类型 | 当前版本标识 | 当前内容哈希 |
| --- | --- | --- | --- | --- |
| jolt | `jolt` | release tag | v5.5.0 | `N-V-__8AAAPKDAINa53XiVzIJ2I4V3AAjPxzQ_bJ9TD7TOOS` |
| cgltf | `cgltf` | release tag | v1.15 | `N-V-__8AAKFjBABZzn84N4iiLQyNQSMVsv5XBJSvZTPcQL2H` |
| stb | `stb` | 提交 SHA | `f0569113c93ad095470c54bf34a17b36646bbbb5` | `N-V-__8AAJopTgBuYbPPno6GEtqFAeIhKHyhTJcJ-Vp2FpHj` |
| imgui | `imgui` | release tag | v1.92.5 | `N-V-__8AALp9cwA8tEuEno2YCZyivsMaobnF-Z7qZGY3qBOt` |
| miniaudio | `miniaudio` | release tag | 0.11.26 | `N-V-__8AAOYywgDjFH2rxtvPz3D1RS7WRGMqfpncZjJW-jIl` |
| sdl3 | `sdl3` | git 固定提交 | `aaa5868464855ab0bda4dffe1cf424709f665669` | `sdl3-0.1.0-WOwCypO_BACuJ0ijR3Y3kamzX0Ds_uzIaY-ucLwBdPog` |

**T010 覆盖率核对**：R1 的 6 个名称与 `build.zig.zon` `.dependencies` 的键完全一致（6/6，100%），每项均记录了当前版本、哈希、上游最新版本与结论；本阶段未修改 `build.zig.zon`（满足 SC-001）。

上游 SDL 本体最新为 `release-3.4.20`（2026-11-03），与当前绑定版本一致，因此 sdl3-zig 无需升级。

**Rationale**：以官方仓库 API 返回为准，不使用猜测版本或浮动分支引用；stb 与 sdl3-zig 按提交哈希固定，故以其默认分支最新提交作为「最新版本」。

**Alternatives considered**：使用 `main`/`master` 分支 URL（拒绝：浮动引用违反 FR-004 与宪章 I）；仅凭版本号主观判断（拒绝：无法保证精确哈希）。

## R2 — Jolt v5.7.0 与现有 C ABI 桥接是否兼容？

**Decision**：作为候选升级，以 `zig build physics-test` 与 `zig build install test` 为唯一判定门禁；若失败则回退 v5.5.0 并记录「工具链/API 不兼容」。

**Rationale**：`build.zig` 的 `configurePhysics()` 会从 `Jolt/Jolt.cmake` 解析 `JOLT_PHYSICS_SRC_FILES` 源码列表，并通过 `src/engine/physics/jolt_bridge.cpp/.h` 以 C ABI + TranslateC 接入。v5.7.0 若调整源列表组织方式或 C ABI 签名，会直接导致构建或测试失败；这类风险只能实测，不能静态断言。

**Alternatives considered**：跳过 Jolt 升级（拒绝：它是明确存在更新的直接依赖，需先评估）；升级并放宽门禁（拒绝：违反 FR-005/FR-007 与宪章 II）。

## R3 — ImGui v1.93.0 的 SDL3 / SDL GPU 后端是否兼容？

**Decision**：作为候选升级，以核心测试、`-Ddemo-2d=true` 与 `-Dclear-only=true` 的独立构建测试及 UI 手动验收为门禁；失败则回退 v1.92.5。

**Rationale**：项目直接编译 `imgui.cpp`、`imgui_impl_sdl3.cpp`、`imgui_impl_sdlgpu3.cpp` 与自写 `imgui_bridge.cpp`。ImGui 次版本升级可能改变后端接口或绘制数据结构，需要编译与画面验收双重确认。

**Alternatives considered**：只升级核心库不升级后端（不可行：仓库按 tag 整体获取）。

## R4 — stb master HEAD 是否可安全替换固定提交？

**Decision**：作为候选升级，以纹理解码相关测试与默认训练场验收（含 `缓存命中 embedded:demo.glb`）为门禁；失败则回退 `f056911`。

**Rationale**：stb 为单头文件库、API 稳定，但 master 提交不等于发布版本；需以实际构建与画面验收确认 PNG/JPEG 解码行为未变。

**Alternatives considered**：等待正式 release（stb 无版本发布机制，不可行）。

## R5 — sdl3-zig / SDL / 工具链是否需要升级？

**Decision**：sdl3-zig 与 SDL 保持原样；Zig 工具链保持 0.17.1，不作任何升级或校验放宽。

**Rationale**：二者均为上游最新；Zig 被宪章 I 精确锁定，且 SC-005 要求整个过程版本不变。若某依赖的更新要求更高 Zig 版本，按规格边界条件「工具链不兼容」保持原样。

**Alternatives considered**：为升级依赖而升级 Zig（拒绝：违反宪章 I 与 FR-005）。

## R6 — 升级后的哈希与离线构建如何保证？

**Decision**：每项升级用 `zig fetch <url>` 获取新 URL 的精确内容哈希，再将 URL 与哈希写回 `build.zig.zon`（或用 `zig fetch --save=<name> <url>` 直接写入）；升级完成后在干净工作树执行离线构建。失败时定位导致失败的依赖并逐项回退，直到离线构建通过。

**Rationale**：`build.zig.zon` 的 `hash` 字段是离线可复现构建的前提；`zig-pkg/` 为本地缓存，不能作为哈希可信来源。

**Alternatives considered**：手工填写哈希或从缓存推断（拒绝：无法保证跨环境一致）。

## 未解决项

无。所有 Technical Context 中的未知项均已在 R1–R6 中形成可执行决策；兼容性不明项已转化为「候选升级 + 门禁判定 + 回退」的明确流程。
