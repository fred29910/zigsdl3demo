# AGENTS.md — zigsdl3demo 代理工作指南

<!-- SPECKIT START -->
For additional context about technologies to be used, project structure,
shell commands, and other important information, read the current plan
<!-- SPECKIT END -->

本文件供在本仓库中工作的 AI 编码代理阅读。目标是在**不破坏已验收行为**的前提下做增量改动。开始前先读 [README.md](README.md)，它包含完整的操作说明、架构、依赖与验收记录。

## 1. 项目概览

- **性质**：用 Zig + SDL3 构建的第一人称训练场 Demo，同时是《FPS 框架开发计划》的可运行验证工程。
- **状态**：里程碑 M0–M11 已完成并记录；默认训练场、2D 输入演示、Vulkan 清屏模式、glTF/GLB 查看器均可运行。
- **主语言**：Zig 0.17.1；少量 C/C++ 桥接（Jolt、cgltf/stb、miniaudio、ImGui）。
- **文档语言**：README、设计文档、源码顶层注释与日志均为**中文**；标识符、命令、路径保持英文。新增注释与提交信息沿用中文。

| 文档 | 内容 |
| --- | --- |
| [README.md](README.md) | 快速开始、操作、运行模式、架构、依赖、着色器、测试验收、常见问题 |
| [docs/Zig_SDL3_FPS_Framework_Plan.docx](docs/Zig_SDL3_FPS_Framework_Plan.docx) | 框架设计计划（M0–M11） |
| [docs/M11_Performance.md](docs/M11_Performance.md) | Tracy 性能采样方法与结果 |
| [build.zig.zon](build.zig.zon) | 依赖的 URL、哈希与版本（唯一可信来源） |

## 2. 硬性约束（违反会直接破坏构建或验收）

1. **Zig 版本必须精确为 0.17.1**。`build.zig` 顶部用 `@compileError` 校验 `builtin.zig_version_string`；不要升级 Zig 或放宽该检查，除非项目整体升级并重新验证全部里程碑。编辑器可搭配 ZLS 0.17.0。
2. **依赖必须锁版本与哈希**。所有第三方依赖在 `build.zig.zon` 中固定；不要用浮动版本或 `zig fetch` 覆盖哈希。首次构建需要联网，之后应可离线构建。
3. **不要修改生成物与缓存目录**：`zig-pkg/`、`zig-out/`、`.zig-cache/` 均为本地生成内容，已在 `.gitignore` 中忽略。
4. **SPIR-V 与 HLSL 必须同步**。仓库提交的 `.spv` 与对应 `.hlsl` 需配套更新；普通构建优先使用已提交的 SPIR-V，只有显式提供 `shadercross`（或 `-Dshadercross`）时才离线重编译。
5. **不要手工编辑 Spec Kit 生成的受管文件**（`.opencode/commands/`、`.specify/templates/`、`.specify/scripts/` 等）。定制应通过 preset、project-local override 或扩展完成。
6. **不要破坏两种基础演示模式**：`-Ddemo-2d=true` 与 `-Dclear-only=true` 会跳过 Jolt、资产导入、ImGui、音频集成；改动构建图时需保证这些分支仍能独立构建与测试。
7. **未实机验证的项不能当作已验证**：真实 GPU 桌面窗口管理器、物理播放设备尚未验证；Linux 虚拟显示 + Mesa Lavapipe 是验收基线。

## 3. 构建、运行与测试

```sh
zig version                                   # 必须是 0.17.1
zig build                                     # Debug 安装到 zig-out/bin/
zig build run                                 # 默认内嵌训练场
zig build run -- assets/demo.glb              # 外部模型查看模式
zig build run -Ddemo-2d=true                  # M1 2D 输入演示
zig build run -Dclear-only=true               # M2 Vulkan 清屏
zig build -Doptimize=ReleaseSafe --prefix zig-out/release   # 发布版，独立输出目录
```

```sh
zig build install test                        # 核心/SDL/场景/资产/物理单元测试
zig build install test -Doptimize=ReleaseSafe # 发布安全模式复测
zig build physics-test                        # Jolt 无窗口物理测试
zig build test -Ddemo-2d=true                 # 2D 模式测试
zig build test -Dclear-only=true              # 清屏模式测试
```

**任何改动至少要求 `zig build install test` 通过**；涉及物理、碰撞、角色、武器时还要跑 `zig build physics-test`。

着色器更新流程（需要支持 DXC 的 `shadercross`）：

```sh
zig build shaders -Dshadercross=/path/to/shadercross
for shader in shaders/*.spv; do
  cmp "$shader" "zig-out/$shader" || exit 1
done
```

无桌面冒烟测试可用 `SDL_VIDEODRIVER=offscreen`（M2 + Lavapipe）或 `SDL_VIDEODRIVER=dummy SDL_RENDER_DRIVER=software`（M1），具体命令见 README「无桌面冒烟测试」。

## 4. 架构地图

数据流：

```
SDL 事件 → InputState → 相机转向 / 角色输入
  ↓
Jolt 固定步进（1/60s，每帧最多 6 步）→ 同步实体位姿与相机
  ↓
开火/换弹 → 敌人状态机、攻击、回合结算
  ↓
Render Queue → 阴影 → 不透明场景 → 天空盒 → HUD / ImGui
```

| 路径 | 职责 |
| --- | --- |
| `src/main.zig` | 入口、构建模式选择、SDL 事件循环、窗口生命周期 |
| `src/engine/core` | 日志与分配器 |
| `src/engine/platform/sdl` | 窗口、事件、键鼠输入、相对鼠标模式、逻辑/像素尺寸 |
| `src/engine/scene` | Registry、父子变换、模型实例、MeshRenderer |
| `src/engine/assets` | 静态 glTF/GLB 导入、纹理解码、资源句柄与缓存、GPU 上传 |
| `src/engine/physics` | Jolt C ABI 桥接、刚体、碰撞层、射线、胶囊角色、训练场布置 |
| `src/engine/gameplay` | 武器/生命组件、机器人状态机、路点寻路 |
| `src/engine/renderer` | SDL GPU 交换链、相机、Render Queue、光照阴影、天空盒、ImGui |
| `src/engine/audio` | miniaudio 桥接与程序生成的短 PCM 音效 |
| `assets/`、`shaders/` | Blender 导出脚本、GLB、HLSL 与已提交 SPIR-V |
| `src/physics_test.zig` | 无窗口物理/武器测试 |

## 5. 改动约定

- **先定位再修改**：用 codebase-memory-mcp 图工具（如可用）或 grep/glob 找到相关符号后再编辑，避免全文盲改。本仓库**没有 `.codegraph/` 索引**，按全局规则跳过 CodeGraph。
- **保持资源生命周期**：场景实例持有模型引用期间，GPU 资源与句柄必须保持有效；重开回合时先创建新 Jolt 世界与实体，再释放旧世界与旧实体。
- **缓存语义**：文件资源按规范绝对路径缓存，内嵌资源按名称缓存；默认训练场应触发 `缓存命中 embedded:demo.glb`，不要无意中破坏共享。
- **物理参数**：固定步长 1/60s、每帧最多 6 步、相机在胶囊脚点上方 1.6m、射线取最近碰撞；修改这些值需同步更新 README 与验收记录。
- **提交风格**：沿用现有 `feat: ...` 前缀与中文描述；每个里程碑/功能保持原子提交，便于对照 README 的里程碑表。
- **文档同步**：新增或修改功能时，更新 README 对应章节（操作表、架构表、测试与验收、常见问题）以及必要的 `docs/` 记录。

## 6. 已知边界（不要误判为 bug）

- glTF 仅支持静态三角形、Position/Normal/Tangent/UV0、Base Color 纹理与 Alpha Mask、法线贴图、粗糙度系数、`KHR_materials_unlit`；**动画、蒙皮、Morph、压缩网格、GPU Instancing、Alpha Blend、UV1+ 超出范围**。
- 前向渲染为 Blinn–Phong，Metallic/PBR 贴图可导入但尚未接入最终着色路径。
- 音频初始化失败时记录警告并继续运行；默认训练场无声先查启动日志的 `audio` 行与系统输出设备。
- 发布版可直接从任意目录启动（GLB 与 SPIR-V 已嵌入）；若依赖外部 `.bin`/纹理，需保持相对路径。

## 7. Spec Kit 工作流（已启用）

项目已用 `opencode` 集成初始化了 GitHub Spec Kit，并安装了 `agent-context` 扩展。

**Skills / 命令**（在 OpenCode 聊天中调用，用点号）；若新命令未出现，执行 `/reload`：

```
/speckit.constitution   /speckit.specify    /speckit.clarify
/speckit.plan           /speckit.tasks      /speckit.analyze
/speckit.checklist      /speckit.implement  /speckit.converge
/speckit.agent-context.update
```

**Hooks**：`after_specify` 与 `after_plan` 会提示刷新本文件顶部的 `<!-- SPECKIT START -->` / `<!-- SPECKIT END -->` 托管段，使其指向最新 `specs/**/plan.md`。该段由脚本自动维护，**不要手工编辑段内内容**；其他章节可自由修改。若系统 `python3` 缺少 PyYAML（本机即如此，脚本会跳过更新），用可移植方式手动刷新：

```sh
uv run --with pyyaml python .specify/extensions/agent-context/scripts/python/update_agent_context.py
```

**建议流程**：先用 `/speckit.constitution` 把已经成立的项目规则固化为原则（不要发明标准）；后续每个功能按 `/speckit.specify → /speckit.plan → /speckit.tasks → /speckit.implement → /speckit.converge` 推进，并以有界改动为起点，不要把整个既有工程补写成规格。

## 8. 工具与环境提示

- 测试/构建命令一律用 `shell` 执行，工作目录为仓库根目录。
- OpenCode 配置的热更新无需重启服务；必要时用 `/reload`。
- 全局 `AGENTS.md` 中的 CodeGraph 段落对本仓库不适用（无 `.codegraph/`）；MCP 图工具优先级见全局配置。
