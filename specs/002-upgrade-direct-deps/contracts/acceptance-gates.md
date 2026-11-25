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
