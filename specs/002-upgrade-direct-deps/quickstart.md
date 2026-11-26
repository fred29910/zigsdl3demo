# Quickstart: 直接依赖升级验证指南

本指南用于逐项验证依赖升级是否可落地。不包含实现代码；任务拆解见后续 `tasks.md`，判定规则见 [contracts/acceptance-gates.md](contracts/acceptance-gates.md)，数据结构见 [data-model.md](data-model.md)。

## 前置条件

- Zig **0.17.1**（`zig version` 必须精确匹配；`build.zig` 会强制校验）。
- 调研阶段允许联网；`zig fetch` 需要网络。
- 工作树干净，且已记录升级前的 `build.zig.zon` 内容作为回退基线。
- 不使用或修改 `zig-pkg/`、`zig-out/`、`.zig-cache/` 中的内容。

## 步骤

### 1. 盘点基线

```sh
zig version
cat build.zig.zon
```

确认 `.dependencies` 的 6 个键与上游最新版本结论（见 [research.md](research.md) R1）。记录每个依赖的原版本与哈希。

**基线门禁结果（T002，2026-11-25，Zig 0.17.1）**：

| 门禁 | 命令 | 结果 |
| --- | --- | --- |
| G1 | `zig build install test` | 通过（exit 0） |
| G2 | `zig build install test -Doptimize=ReleaseSafe` | 通过（exit 0） |
| G3 | `zig build physics-test` | 通过（exit 0） |
| G4 | `zig build test -Ddemo-2d=true` | 通过（exit 0） |
| G5 | `zig build test -Dclear-only=true` | 通过（exit 0） |

**2026-11-26 重跑 `/speckit.plan` 更新结果（当前锁定状态）**：

- 当前锁定：Jolt v5.7.0、ImGui v1.93.0、stb `6b5799b`、cgltf v1.15、miniaudio 0.11.26、sdl3-zig `aaa5868`（SDL 3.4.20）；`zig version` = 0.17.1。
- `sh specs/002-upgrade-direct-deps/contracts/check-target-versions.sh` → GREEN（9 项全部通过）。
- G1–G5（2026-11-26）：`zig build install test`、`zig build install test -Doptimize=ReleaseSafe`、`zig build physics-test`、`zig build test -Ddemo-2d=true`、`zig build test -Dclear-only=true` 全部退出码 0。
- G6（2026-11-26）：`ZIG_GLOBAL_CACHE_DIR=/tmp/opencode/zig-clean-cache zig build install test --cache-dir /tmp/opencode/zig-clean-local-cache` 退出码 0。
- 外部网络调研状态：见 [research.md](research.md) P1.1（librarian 查询 2026-11-26 最新正式稳定版结果待回填）。

### 2. RED：先写检查并看到失败

依据宪章 II，升级前先编写 `specs/002-upgrade-direct-deps/contracts/check-target-versions.sh`，断言目标版本（imgui v1.93.0、jolt v5.7.0、stb 提交 `6b5799b`）与精确锁定规则。运行该脚本，预期在当前版本下**失败（RED）**；将失败输出写入 `specs/002-upgrade-direct-deps/contracts/acceptance-gates.md` 并取得用户确认后，才允许进入下一步。**未确认前不要修改 `build.zig.zon`。**

### 3. 逐项升级（一次一项）

每次只改一个依赖的 `.url` 与 `.hash`，避免失败时难以定位。候选顺序建议：

1. `imgui` v1.92.5 → v1.93.0
2. `jolt` v5.5.0 → v5.7.0
3. `stb` `f056911` → `6b5799b`

获取哈希并写入：

```sh
zig fetch "<新版本的精确 URL>"    # 输出内容哈希，不改写文件
# 将新 URL 与输出的哈希写入 build.zig.zon 对应依赖项
```

cgltf、miniaudio、sdl3-zig 已是上游最新，保持原样并在 README 记录理由。

### 4. 运行门禁

每项升级后立即执行：

```sh
zig build install test
zig build install test -Doptimize=ReleaseSafe
zig build physics-test
zig build test -Ddemo-2d=true
zig build test -Dclear-only=true
```

预期：全部成功，无新增失败项。任一失败 → 回退该依赖到原版本/哈希，重跑门禁，并在 README 记为「保持原样（门禁失败）」。

### 5. 离线干净构建

在全部升级完成且本地缓存清理后，断开网络执行构建：

```sh
zig build --fetch=all   # 联网预热全部依赖（含 lazy 依赖）
# 使用全新的临时缓存目录模拟干净环境；不要删除仓库内的 zig-pkg/、zig-out/、.zig-cache/
ZIG_GLOBAL_CACHE_DIR=/tmp/opencode/zig-clean-cache zig build --cache-dir /tmp/opencode/zig-clean-local-cache
```

预期：构建成功，证明锁定 URL 与哈希在干净环境可复现。失败则定位依赖并回退，直到通过。

### 6. 留痕

在 `README.md`「技术栈与依赖」章节更新依赖表，对每一项写明：原版本 → 新版本（或保持原样）及理由；确认 Zig 版本仍为 0.17.1，支持边界与不变量未变。

## 完成判定

- 6 项直接依赖 100% 完成评估（SC-001）。
- 浮动版本引用数量为 0（SC-002）。
- G1–G6 全部通过（SC-003/SC-004）。
- Zig 版本与校验未变（SC-005）。
- README 中每个依赖都有可追溯记录（SC-006）。
