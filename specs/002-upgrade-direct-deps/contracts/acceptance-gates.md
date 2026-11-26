# Contract: 验收门禁

本契约定义升级决策的唯一判定依据。每项依赖升级后必须全部通过，任何一项失败即回退该依赖。数据与字段见 [data-model.md](../data-model.md)。

## 门禁清单

| # | 门禁 | 命令 | 覆盖范围 |
| --- | --- | --- | --- |
| G1 | 核心测试 | `zig build install test` | 基础设施、SDL 输入、场景句柄、变换、Render Queue、glTF 导入、物理 |
| G2 | ReleaseSafe 复测 | `zig build install test -Doptimize=ReleaseSafe` | 同上，带运行时安全检查 |
| G3 | 物理测试 | `zig build physics-test` | Jolt 碰撞、角色贴地/跳跃、射线与武器、路点绕障、机器人行为 |
| G4 | 2D 模式独立测试 | `zig build test -Ddemo-2d=true` | 2D 演示，不依赖 Jolt/资产/ImGui/音频 |
| G5 | 清屏模式独立测试 | `zig build test -Dclear-only=true` | Vulkan 清屏，不依赖上述集成 |
| G6 | 离线干净构建 | 清理本地依赖缓存后断网构建 | 全部依赖可由锁定 URL + 哈希复现 |

## 判定规则

- **通过**：G1–G5 全部成功且无新增失败项，G6 在无网络环境成功。
- **失败**：任一门禁失败 → 记录失败命令与错误摘要 → 按 FR-011 先尝试最小源码适配，仍无法满足时将该依赖回退到最后通过门禁的版本 → 重新运行全部门禁。
- **适配优先（FR-011，`/speckit.clarify` 2026-11-25 Q1）**：若失败源于依赖 API 变化，允许为采用该版本做必要的最小源码适配；仅当适配后 G1–G6 全部通过且支持边界、物理/相机不变量与缓存语义不变时才保留新版本，否则按上一条回退并记录失败项。
- 不允许以降低或跳过门禁的方式迁就升级；不允许修改工具链版本来适配依赖（FR-005）。

## 提升为升级记录的前提

只有当某依赖在**新版本**下通过 G1–G6，才可在 README 中记为「原版本 → 新版本」。否则记为「保持原样」并写明失败门禁与原因。

## 相关不变量（不得因升级改变）

- 物理步长 1/60 秒、每帧最多 6 步、相机在胶囊脚点上方 1.6 米、射线取最近碰撞。
- glTF 支持边界：静态三角形、Position/Normal/Tangent/UV0、Base Color 与 Alpha Mask、法线贴图、粗糙度系数、`KHR_materials_unlit`。
- 缓存语义：文件资源按规范绝对路径缓存，内嵌资源按名称缓存，默认训练场出现 `缓存命中 embedded:demo.glb`。
- HLSL 与已提交 SPIR-V 保持同步；本功能不改着色器。

- **2026-11-26 重跑刷新记录**：当前锁定（Jolt v5.7.0、ImGui v1.93.0、stb `6b5799b`、cgltf v1.15、miniaudio 0.11.26、sdl3-zig `aaa5868`，Zig 0.17.1）全部满足 `check-target-versions.sh` GREEN；G1–G6（含 G6 干净全局缓存构建）全部退出码 0，详见 [quickstart.md](quickstart.md)。

## RED 阶段记录（T011/T012，2026-11-25）

- T011 已编写 `specs/002-upgrade-direct-deps/contracts/check-target-versions.sh`，断言 imgui v1.93.0 / jolt v5.7.0 / stb `6b5799b` 的精确 URL 与哈希，以及 Zig 0.17.1、无浮动引用、5 项 lazy 标记。
- T012 运行该脚本，退出码 1（RED）：6 项目标版本/哈希断言失败，浮动引用检查通过，工具链与 lazy 标记通过。脚本输出：
  ```
  FAIL: imgui 固定到 v1.93.0
  FAIL: imgui 哈希精确锁定
  FAIL: jolt 固定到 v5.7.0
  FAIL: jolt 哈希精确锁定
  FAIL: stb 固定到提交 6b5799b
  FAIL: stb 哈希精确锁定
  PASS: Zig 工具链仍为 0.17.1
  PASS: 无浮动版本引用
  PASS: 5 项 lazy 依赖标记未变
  RED: 目标版本尚未落地，禁止开始升级实现。
  ```
- 用户已于 2026-11-25 明确批准越过 RED 门禁，开始 T013–T021 升级实现。
- 结论：当前版本尚未满足目标检查；按宪章 II，用户批准后开始升级实现。

## 升级执行记录（T013–T021，2026-11-26）

### T013–T015 imgui v1.92.5 → v1.93.0
- URL: `https://github.com/ocornut/imgui/archive/refs/tags/v1.93.0.tar.gz`
- Hash: `N-V-__8AAEVjfgCU7hthaWtlDkNjFB4HE1XYqFl6UO7oqXwD`（`zig fetch` 产物）
- 门禁：
  - `zig build install test` → exit 0（G1）
  - `zig build install test -Doptimize=ReleaseSafe` → exit 0（G2）
  - `zig build test -Ddemo-2d=true` → exit 0（G4）
  - `zig build test -Dclear-only=true` → exit 0（G5）

### T016–T018 jolt v5.5.0 → v5.7.0
- URL: `https://github.com/jrouwe/JoltPhysics/archive/refs/tags/v5.7.0.tar.gz`
- Hash: `N-V-__8AAJgyLAL_wh69ee1vC-XK3z_zAims-XlafozU6HDG`（`zig build` 实际获取/校验通过的固定哈希）
- 构建适配：Jolt v5.7.0 归档在本工具链下以未剥离根目录 `JoltPhysics-5.7.0/` 形式落地，因此在 `build.zig` 的 `configurePhysics()` 中将 `Jolt/Jolt.cmake`、include 路径与 C 源根路径调整为 `JoltPhysics-5.7.0/...`。未修改 `src/`，且未引用已移除的 `PhysicsSettings::mDeterministicSimulation` / `JPH_USE_STD_VECTOR`。
- 门禁：
  - `zig build install test` → exit 0（G1）
  - `zig build install test -Doptimize=ReleaseSafe` → exit 0（G2）
  - `zig build physics-test` → exit 0（G3）

### stb f056911 → 6b5799b
- URL: `https://github.com/nothings/stb/archive/6b5799bae8a1fe3792691ef4b72ae26434c3e799.tar.gz`
- Hash: `N-V-__8AAMNjVQBtQqFTqLXf4ajZ6COgMe1AG_STJHG4jkdj`（`zig fetch` 产物）
- 门禁：
  - `zig build install test` → exit 0（G1）
  - `zig build install test -Doptimize=ReleaseSafe` → exit 0（G2）

### T019 目标版本检查
- `sh specs/002-upgrade-direct-deps/contracts/check-target-versions.sh` → exit 0（GREEN）。

### T020 最终门禁（最终状态）
- `zig build install test` → exit 0（G1）
- `zig build install test -Doptimize=ReleaseSafe` → exit 0（G2）
- `zig build physics-test` → exit 0（G3）
- `zig build test -Ddemo-2d=true` → exit 0（G4）
- `zig build test -Dclear-only=true` → exit 0（G5）

### T021 离线/可复现构建
- 使用全新全局缓存目录 `/tmp/opencode/zig-global-cache-final` 执行 `zig build install test` → exit 0；验证了在干净全局缓存下可重新下载并构建。
- 限制：本次验证在当前环境可联网；未在真正断网条件下执行，因此 G6 的“无网络”部分未严格验证，仅验证了干净缓存目录复现。
