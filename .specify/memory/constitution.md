<!--
  Sync Impact Report — 临时审阅材料，提交前删除
  Version change: N/A → 1.0.0（首次采纳，非修订）
  Modified principles（模板占位符 → 具体原则）:
    - PRINCIPLE_1_NAME → I. 精确版本与锁定依赖
    - PRINCIPLE_2_NAME → II. 测试先行与验收门禁（NON-NEGOTIABLE）
    - PRINCIPLE_3_NAME → III. 增量改动与零回归
    - PRINCIPLE_4_NAME → IV. 资源生命周期与确定性状态
    - PRINCIPLE_5_NAME → V. 简洁克制与边界清晰
  Added sections:
    - 图形、物理与着色器不变量
    - 开发工作流与质量门禁
    - Governance（填充具体规则）
  Removed sections: 无（仅移除模板示例注释）
  Follow-up TODOs: 无
-->
# Zig SDL3 Demo Constitution

## Core Principles

### I. 精确版本与锁定依赖
构建工具链与第三方依赖必须精确锁定，禁止浮动版本：
- 构建脚本必须用 `@compileError` 校验 Zig 版本精确为 0.17.1；不得升级 Zig 或放宽该检查，除非整体升级并重新验证全部里程碑。
- 所有第三方依赖的版本、提交与内容哈希必须在 `build.zig.zon` 中固定；禁止用浮动版本或 `zig fetch` 覆盖哈希。
- 首次构建允许联网，之后必须可离线构建。普通构建优先使用仓库已提交的 SPIR-V，只有显式提供 `shadercross` 时才离线重编译。
理由：可复现的构建是 M0–M11 验收记录成立的前提，版本漂移会直接破坏构建与已验收行为。

### II. 测试先行与验收门禁（NON-NEGOTIABLE）
- 所有功能与缺陷修复遵循 Red-Green-Refactor：先写测试并获得用户确认，看到测试失败后再实现。
- 任何改动至少要求 `zig build install test` 通过；涉及物理、碰撞、角色或武器时还必须运行 `zig build physics-test`。
- 两个基础演示模式（`-Ddemo-2d=true` 与 `-Dclear-only=true`）必须能独立构建与测试，构建图改动不得让它们依赖 Jolt、资产导入、ImGui 或音频集成。
理由：本工程是 FPS 框架计划的可运行验证工程，回归即意味着验收结论失效。

### III. 增量改动与零回归
- 一切改动必须是增量的，不得破坏已验收行为；先定位相关符号再编辑，禁止全文盲改。
- 不手工编辑生成物与缓存目录（`zig-pkg/`、`zig-out/`、`.zig-cache/`）。
- 未实机验证的项（真实 GPU 桌面窗口管理器、物理播放设备）不得当作已验证；Linux 虚拟显示 + Mesa Lavapipe 是唯一验收基线。
理由：已验收的 M0–M11 是受保护基线，小幅原子改动便于对照与回滚。

### IV. 资源生命周期与确定性状态
- 场景实例持有模型引用期间，GPU 资源与句柄必须保持有效；重开回合时先创建新 Jolt 世界与实体，再释放旧世界与旧实体。
- 缓存语义必须保持：文件资源按规范绝对路径缓存，内嵌资源按名称缓存；默认训练场必须触发 `缓存命中 embedded:demo.glb`。
- 物理与相机不变量必须保持：固定步长 1/60 秒、每帧最多 6 步、相机在胶囊脚点上方 1.6 米、射线取最近碰撞。修改这些值需同步更新 README 与验收记录。
理由：生命周期错误会导致悬垂引用与缓存失效，物理参数漂移会改变已验证的交互结果。

### V. 简洁克制与边界清晰
- 遵循 YAGNI，不做投机性功能；公开的功能支持范围必须在 README 中明确记录。
- glTF/GLB 导入限于静态三角形、Position/Normal/Tangent/UV0、Base Color 纹理与 Alpha Mask、法线贴图、粗糙度系数与 `KHR_materials_unlit`；动画、蒙皮、Morph、压缩网格、GPU Instancing、Alpha Blend 与 UV1+ 超出范围。
- 前向渲染采用 Blinn–Phong；Metallic/PBR 贴图可导入但不在当前着色路径生效。
理由：清晰的边界让实现、测试与文档保持一致，避免对不支持的能力做隐含承诺。

## 图形、物理与着色器不变量

- 前向管线使用 2048×2048 方向光阴影图与 3×3 PCF 采样；主 Pass 与阴影 Pass 必须使用相同的 Alpha Mask 阈值。
- 法线贴图使用线性采样；缺少切线的模型可由屏幕导数重建切线空间；天空盒来自程序生成的六面立方体贴图。
- 仓库提交的 `.spv` 必须与对应 `.hlsl` 同步更新；更新 HLSL 后须用支持 DXC 的 shadercross 生成新产物并逐字节核对。
- 上述不变量属于验收基线，任何变更都需要重新验证相关里程碑并更新 README「测试与验收」。

## 开发工作流与质量门禁

- 功能推进采用 Spec Kit 工作流：`/speckit.specify` → `/speckit.plan` → `/speckit.tasks` → `/speckit.implement` → `/speckit.converge`，以有界改动为起点。
- 编辑前用 codebase-memory-mcp 图工具或 grep/glob 定位相关符号；本仓库没有 `.codegraph/` 索引。
- 新增或修改功能时同步更新 README（操作表、架构表、测试与验收、常见问题）及必要的 `docs/` 记录。
- 提交沿用 `feat:` / `docs:` / `chore:` 前缀与中文描述，每个里程碑或功能保持原子提交。
- 文档语言为中文；标识符、命令与路径保持英文；新增注释与提交信息沿用中文。

## Governance

本宪章是本项目治理的最高准则，与任何开发实践冲突时以本宪章为准。所有 PR 与评审必须验证是否符合本宪章；任何偏离都必须给出书面理由并记录在对应规格或验收记录中。复杂度必须有明确收益支撑，违反简洁原则的改动需要说明必要性。

修订流程：任何原则或章节的增删改必须通过更新本文件完成，并在文件顶部的 Sync Impact Report 中记录版本变化、修改项与后续 TODO；报告属临时审阅材料，提交前删除。修订需项目维护者审阅通过，并同步更新受影响的规格、计划与 README 验收记录。

版本策略遵循语义化版本：MAJOR 用于向后不兼容的治理或原则移除与重定义；MINOR 用于新增原则/章节或实质性扩展；PATCH 用于澄清、措辞与错别字修正。合规审查在每次里程碑验收与 PR 评审时进行，未通过不得合并。运行时开发 guidance 见 [AGENTS.md](AGENTS.md) 与 [README.md](README.md)。

**Version**: 1.0.0 | **Ratified**: 2026-11-25 | **Last Amended**: 2026-11-25
