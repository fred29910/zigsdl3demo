# Zig SDL3 Demo

用 Zig 和 SDL3 构建的第一人称训练场，也是 [FPS 框架开发计划](docs/Zig_SDL3_FPS_Framework_Plan.docx) 的可运行验证项目。默认场景包含可冲刺和跳跃的胶囊角色、固定靶板和一个会巡逻、追击并攻击的训练机器人。玩家可以打完一局并在原窗口重开。工程还提供 glTF/GLB 查看器、SDL 2D 输入演示和 Vulkan 清屏模式。

首期 M0–M11 的功能及运行验证见 [测试与验收](#测试与验收)。Tracy 采样方法和结果见 [M11 性能记录](docs/M11_Performance.md)。

## 目录

- [快速开始](#快速开始)
- [操作与训练场](#操作与训练场)
- [运行模式与构建](#运行模式与构建)
- [游戏大厅](#游戏大厅)
- [加载外部 glTF 或 GLB](#加载外部-gltf-或-glb)
- [架构与目录](#架构与目录)
- [技术栈与依赖](#技术栈与依赖)
- [着色器开发](#着色器开发)
- [编辑训练场](#编辑训练场)
- [测试与验收](#测试与验收)
- [常见问题](#常见问题)

## 快速开始

- **构建工具**使用 Zig **0.17.1**。构建脚本检查精确版本，编辑器可搭配 ZLS **0.17.0**。
- **运行环境**以 Linux 桌面为验收基线。3D 与清屏模式需要 Vulkan loader、支持 SPIR-V 的 Vulkan 驱动及可用的 SDL 视频后端。可使用 Mesa Lavapipe 进行软件渲染验收。
- **首次构建**需要联网获取锁定依赖。Zig 会从源码构建 SDL **3.4.20**。常规构建可直接嵌入仓库中的 SPIR-V。

```sh
zig version
zig build run
```

窗口打开后，按 **Tab** 捕获鼠标并开始，按 **WASD** 移动。击倒远端围墙前的蓝色靶板和橙色巡逻机器人即可通关。左键开火，**R** 换弹，回合结束后按 **E** 重开，**Esc** 返回大厅（大厅内不退出）。

## 操作与训练场

| 操作 | 默认训练场 | 外部模型模式 |
| --- | --- | --- |
| Tab | 开始或暂停训练并切换鼠标捕获 | 捕获或释放鼠标 |
| 鼠标移动 | 捕获后转动视角 | 捕获后转动视角 |
| W / A / S / D | 前进、左移、后退、右移 | 按相机朝向飞行 |
| 左 Shift | 冲刺 | 加速飞行 |
| 空格 | 着地时跳跃 | 上升 |
| 左 Ctrl | — | 下降 |
| 鼠标左键 | 点击或按住开火 | — |
| R | 换弹 | — |
| E | 在胜负结算后重开 | — |
| Esc / 关闭窗口 | 模式内返回大厅；大厅内不退出 | 退出 |

失焦或最小化时会清除按住的动作、释放鼠标并暂停当前回合。释放鼠标后，可拖动左上角调试面板的 `Rotation` 滑块调整旋转展示物。

- **移动**由 Jolt 胶囊角色处理。角色沿地面移动，抵达斜向围墙时可沿墙滑动，也可跳上出生点左侧的低障碍。调试面板会显示着地状态、刚体数、当前帧的物理步数和最近命中距离。
- **开火**使用相机位置和朝向发出的射线。墙、地面和其他刚体能挡住靶子。训练武器每次造成 25 点伤害，弹匣 6 发，射速上限每秒 4 发，换弹约 1.2 秒，备弹不限。未命中也会消耗弹药。
- **机器人**有 75 HP，沿固定巡逻点移动。发现玩家后会追击，绕过场内掩体。玩家在视线畅通且进入攻击距离时，机器人蓄力后每次造成 20 点伤害。掩体阻挡视线后可中断蓄力。
- **反馈**分三种颜色。蓝色表示碰到表面，黄色表示造成伤害，红色表示击倒。靶板有 100 HP，四次命中后调试面板显示 `Target down`，靶板仍参与碰撞。机器人被击倒后从场景和碰撞世界移除。
- **HUD 和音效**显示玩家生命、弹匣、换弹进度和 FPS。调试面板显示两个目标的进度、机器人的状态和剩余生命。开火声和命中提示音可叠加。
- **结算**在两个目标均被击倒时显示 `Range cleared`，玩家生命归零时显示 `Training failed`。按 **E** 恢复出生点、视角、生命、弹药、目标与动态刚体。

## 运行模式与构建

| 命令 | 用途 |
| --- | --- |
| `zig build run` | 构建并启动内嵌训练场 |
| `zig build run -- assets/demo.glb` | 将同一个 GLB 作为外部模型查看 |
| `zig build run -- "/path/to/scene.gltf"` | 查看本地静态 glTF 场景 |
| `zig build run -Ddemo-2d=true` | 启动 M1 2D 输入演示，检查窗口事件、方向键位和鼠标增量 |
| `zig build run -Dclear-only=true` | 启动 M2 Vulkan 深蓝色清屏，检查设备和交换链 |
| `zig build` | 安装 Debug 可执行文件到 `zig-out/bin/zigsdl3demo` |
| `zig build -Doptimize=ReleaseSafe` | 构建带运行时安全检查的发布版本 |
| `zig build --help` | 查看构建步骤、目标选项和安装路径 |

两种基础演示模式应分别启动。各自的构建会跳过 Jolt、资产导入、ImGui 和 miniaudio 的场景集成。使用 `--prefix` 可为不同配置指定独立的输出目录。下例将 ReleaseSafe 安装到单独的目录，默认目录可继续用于 Debug。

```sh
zig build -Doptimize=ReleaseSafe --prefix zig-out/release
./zig-out/release/bin/zigsdl3demo
```

发布版将 GLB 和 SPIR-V 嵌入可执行文件，可从任意当前目录直接启动。Tracy 通过 `-Dtracy-source` 单独启用。

## 游戏大厅

启动程序后先进入中文游戏大厅，再选择模式进入。四个入口：开始训练（默认训练场）、外部模型预览（自由飞行查看 GLB/glTF）、2D 输入演示、Vulkan 清屏演示。大厅提供两项会话设置：视角灵敏度（0.5–2.0，默认 1.0）与音量（0–100，默认 100），设置不持久化，仅当前会话有效。训练场等模式内按 Esc 返回大厅；大厅内按 Esc 不退出，程序退出通过大厅「退出」按钮或关闭窗口触发。界面中文文字使用随仓库提供的 Droid Sans Fallback 字体（`assets/DroidSansFallbackFull.ttf`）。字体许可：Droid Sans Fallback 字体随仓库提供，用于中文界面。

## 加载外部 glTF 或 GLB

```sh
zig build run -- assets/demo.glb
zig build run -- "/path/to/scene with spaces.gltf"
```

传入模型路径会进入自由飞行查看模式，只加载路径中的场景。练习场的碰撞对象、角色、靶板和武器、HUD 与音效由默认内嵌模式创建。查看外部模型时，使用自由飞行在模型的原始位置和比例下浏览。

| 项目 | 当前支持范围 |
| --- | --- |
| 场景与几何 | glTF 2.0 静态三角形、多节点、多网格、多 primitive、索引和非索引几何、矩阵或 TRS 节点 |
| 顶点属性 | Position、Normal、Tangent、UV0。纹理材质需要 UV0 |
| 本地资源 | GLB buffer view、模型目录下的相对路径、base64 data URI。外部 `.bin`、PNG 和 JPEG 随模型一起放置 |
| 材质 | Base Color 纹理和系数、不透明与 Alpha Mask、法线贴图和 `normalTexture.scale`、粗糙度系数、`KHR_materials_unlit` |
| 必需扩展 | 当前接受 `KHR_materials_unlit` 和 `KHR_mesh_quantization` |
| 渲染范围 | Blinn–Phong 前向渲染。Metallic 和 Metallic/Roughness 贴图可导入，留给 PBR 路径使用 |

动画、蒙皮、Morph、压缩网格、GPU Instancing 扩展、Alpha Blend、纹理坐标变换和 UV1 及以上通道目前超出支持范围。导出时选择静态三角网格、PNG/JPEG 与 UV0，可直接使用 glTF Binary（`.glb`）打包模型和纹理。

## 架构与目录

```text
SDL 事件 → InputState → 应用相机转向和角色输入
  ↓
Jolt 固定步进，同步实体位姿并更新相机位置
  ↓
处理开火与换弹 → 更新敌人状态、攻击与回合结果
  ↓
Render Queue → 阴影 → 不透明场景 → 天空盒 → HUD / 调试面板
```

| 路径 | 职责 |
| --- | --- |
| [src/main.zig](src/main.zig) | 应用入口、构建模式选择、SDL 事件循环及窗口生命周期 |
| [src/engine/core](src/engine/core) | 日志与分配器辅助设施 |
| [src/engine/platform](src/engine/platform) | SDL 窗口、事件、键鼠动作、相对鼠标模式和逻辑/像素尺寸 |
| [src/engine/scene](src/engine/scene) | 实体及组件 Registry、父子变换、模型实例和 MeshRenderer |
| [src/engine/assets](src/engine/assets) | 静态 glTF 导入、纹理解码、带代数的资源句柄、资源缓存和 GPU 上传 |
| [src/engine/physics](src/engine/physics) | Jolt C ABI 桥接、刚体、碰撞层、射线、胶囊角色及训练场布置 |
| [src/engine/gameplay](src/engine/gameplay) | 武器与生命组件、机器人状态机和路点寻路 |
| [src/engine/renderer](src/engine/renderer) | SDL GPU 交换链、相机、Render Queue、光照阴影、天空盒和 ImGui |
| [src/engine/audio](src/engine/audio) | miniaudio 桥接与训练场的短 PCM 开火、命中音效 |
| [assets](assets)、[shaders](shaders) | Blender 场地导出脚本、内嵌 GLB、HLSL 与默认嵌入的 SPIR-V |
| [src/physics_test.zig](src/physics_test.zig) | Jolt 碰撞、角色移动和武器事件的无窗口测试 |

资产从文件加载时按规范绝对路径缓存，内嵌资源按名称缓存。同一个模型可由多实体共享网格、纹理和材质。场景实例持有模型引用期间，对应 GPU 资源和句柄保持可用。默认训练场会重复请求一次模型，启动日志应出现 `缓存命中 embedded:demo.glb`。

Jolt 提供 Box、Sphere、Capsule 和静态三角网格，使用静态、动态两种刚体层。模拟步长是 1/60 秒，每帧最多运行六个物理步。动态刚体位置和旋转以物理状态为准，渲染缩放与父子变换由场景管理。相机跟随胶囊脚点上方 1.6 米，射线从该位置出发并查询最近碰撞。

训练场的场地网格、GPU 资源和音频贯穿窗口生命周期。重开时先创建新 Jolt 世界与回合实体，再释放旧世界与旧实体。机器人使用 Jolt 运动学碰撞体，导航在水平面内通过可见路点搜索最短通路，按掩体边界和机器人宽度判定线段可达性。

前向管线使用 2048×2048 方向光阴影图和 3×3 PCF 采样。主 Pass 着色与阴影 Pass 采用相同的 Alpha Mask 阈值。法线贴图使用线性采样，缺少切线的模型可由屏幕导数重建切线空间。天空盒来自程序生成的六面立方体贴图。

## 技术栈与依赖

版本、提交及内容哈希以 [build.zig.zon](build.zig.zon) 为准。

| 依赖 | 固定版本 | 用途 |
| --- | --- | --- |
| [sdl3-zig](https://github.com/fred29910/sdl3-zig/tree/aaa5868464855ab0bda4dffe1cf424709f665669) | `aaa5868`，绑定 SDL 3.4.20 | 窗口、输入、SDL GPU |
| [Dear ImGui](https://github.com/ocornut/imgui/tree/v1.92.5) | v1.92.5 | HUD、调试面板及 SDL3 / SDL GPU 后端 |
| [Jolt Physics](https://github.com/jrouwe/JoltPhysics/releases/tag/v5.5.0) | v5.5.0 | 刚体、射线和 CharacterVirtual |
| [cgltf](https://github.com/jkuhlmann/cgltf/releases/tag/v1.15) | v1.15 | glTF / GLB 解析 |
| [stb_image](https://github.com/nothings/stb/tree/f0569113c93ad095470c54bf34a17b36646bbbb5) | v2.30，提交 `f056911` | PNG 和 JPEG 解码 |
| [miniaudio](https://github.com/mackron/miniaudio/releases/tag/0.11.26) | 0.11.26 | 短 PCM 音效混音与播放 |
| [Tracy](https://github.com/wolfpld/tracy/tree/v0.12.2) | v0.12.2，可选 | 本地 CPU 帧标记与分区计时 |

**直接依赖升级记录**（原版本 → 新版本/保持原样及理由，仅限 `build.zig.zon` 声明的直接依赖）：

| 依赖 | 原版本 | 新版本 | 理由 |
| --- | --- | --- | --- |
| sdl3-zig | `aaa5868`（SDL 3.4.20） | 保持 `aaa5868`（SDL 3.4.20） | 上游已是最新，无需升级 |
| Dear ImGui | v1.92.5 | v1.93.0 | 上游稳定版发布；G1/G2/G4/G5 门禁通过 |
| Jolt Physics | v5.5.0 | v5.7.0 | 上游稳定版发布；归档目录变化已在 `build.zig` 适配，G1/G2/G3 门禁通过 |
| cgltf | v1.15 | 保持 v1.15 | 上游已是最新，无需升级 |
| stb_image | 提交 `f056911` | 提交 `6b5799b` | 无发布机制，取 master 最新提交；G1/G2 门禁通过 |
| miniaudio | 0.11.26 | 保持 0.11.26 | 上游已是最新，无需升级 |

Tracy 为可选外部源码（经 `-Dtracy-source` 指定本地路径使用），不在直接依赖清单内，本次不纳入升级评估。

Zig 直接编译 Jolt 核心源码，通过 C ABI 和 TranslateC 接入 Zig 0.17.1。规划阶段试验过的 [zphysics 提交](https://github.com/zig-gamedev/zphysics/tree/1414dba86b281f89d72f81a5936ab5d03c15b2b9) 使用旧版 Zig 优化枚举，因此当前采用直接桥接。miniaudio 音效在训练场初始化时生成，运行时无需外部音效文件。

## 着色器开发

普通构建在找不到 `shadercross` 时使用 [shaders](shaders) 下已提交的 SPIR-V。若 `PATH` 中存在 `shadercross`，或通过 `-Dshadercross` 指定路径，构建会离线编译 HLSL 并嵌入生成结果。更新 HLSL 后，用支持 DXC 的 SDL_shadercross 生成新产物。

```sh
zig build shaders -Dshadercross=/path/to/shadercross
```

生成文件位于 `zig-out/shaders`。把更新的 `.spv` 与对应 HLSL 一同提交。使用相同工具链验证提交的 SPIR-V 是否与重新生成的产物一致。

```sh
for shader in shaders/*.spv; do
  cmp "$shader" "zig-out/$shader" || exit 1
done
```

仓库中的 SPIR-V 曾使用 [SDL_shadercross 1ff05be](https://github.com/libsdl-org/SDL_shadercross/tree/1ff05bec573988a98ef9e0260b4da44f512b8367) 和 [DXC v1.8.2505.1](https://github.com/microsoft/DirectXShaderCompiler/releases/tag/v1.8.2505.1) 重新生成并逐字节核对。可执行文件启动时无需 shadercross 或外部 shader 文件。

## 编辑训练场

[Blender 导出脚本](assets/export_range.py) 生成 [range.glb](assets/range.glb)。`Solid_*` 节点提供渲染网格和轴对齐的 Jolt 盒体边界。空节点保存玩家出生点、靶板和箱子的中心、巡逻点 `Patrol_0`–`Patrol_3` 和导航点 `Nav_0`–`Nav_7`。修改障碍位置时，让导航点保留足够的通行空间。发布构建直接嵌入导出的 GLB。

```sh
blender -b -noaudio --python-exit-code 1 --python assets/export_range.py
zig build run
```

## 测试与验收

```sh
zig build install test
zig build install test -Doptimize=ReleaseSafe
zig build physics-test
zig build test -Ddemo-2d=true
zig build test -Dclear-only=true
```

`zig build test` 覆盖基础设施、SDL 输入、场景句柄、父子变换、Render Queue、glTF 导入和物理。`zig build physics-test` 可独立验证碰撞、角色贴地和跳跃、射线与武器、路点绕障、机器人追击与遮挡中断攻击，无需窗口或 GPU。

### 手动验收

1. 默认训练场启动后应显示棋盘格模型、场地、天空盒和随展示物移动的阴影。按 Tab 后，右侧小立方体从空中落地，调试面板报告 10 个 Jolt 刚体和 18 次不透明绘制。
2. 按 Tab 捕获鼠标，验证走、跑、跳和沿墙滑动。按住空格应只触发一次起跳，跳上左侧低障碍后应恢复着地状态。
3. 连续命中正前方靶板四次，观察靶板生命降至 0、黄色命中标记及红色击倒标记。朝地面开火应出现蓝色标记。
4. 朝天空开火，应消耗弹药并仅播放开火声。打空后按 R，确认换弹进度和完成后弹匣回到 6 发。命中时应同时听到较高的提示音。
5. 调整窗口尺寸，确认 HUD 重新定位、场景继续提交帧，释放鼠标后准星隐藏。检查 Esc 与窗口关闭两条退出路径。
6. 运行 M1 2D 模式，检查 WASD、快速点击左键、Tab 捕获、失焦和窗口缩放。运行 M2 清屏模式，检查深蓝色清屏、窗口缩放和最小化后恢复。
7. 用外部 GLB 或 glTF 启动查看模式，检查节点变换、纹理和自由飞行。对含外部缓冲区的场景，保留原相对路径后再运行。
8. 朝机器人接近，观察调试面板从 `Patrol` 变为 `Chase` 和 `Attack`。持续停在攻击范围内，确认玩家死亡后显示 `Training failed`。按 E 重开，击倒机器人和靶板，确认显示 `Range cleared`。再次按 E，检查起始生命、弹药、目标和刚体都已恢复。
9. 大厅冒烟：启动后应先显示中文大厅；进入训练场后按 Esc 返回大厅；大厅内按 Esc 不退出，需关闭窗口退出。验收细节与决策依据见 `specs/001-game-lobby-ui/ui-design.md` D-01–D-18。

### 无桌面冒烟测试

在已安装 Mesa Lavapipe 的 Linux 上，可用支持 Vulkan headless surface 的 SDL `offscreen` 后端验证 M2 的启动、清屏和退出。ICD 路径按本机调整。

```sh
zig build -Dclear-only=true --prefix zig-out/clear
timeout --preserve-status --kill-after=2s 3s env \
  SDL_VIDEODRIVER=offscreen \
  VK_DRIVER_FILES=/usr/share/vulkan/icd.d/lvp_icd.json \
  ./zig-out/clear/bin/zigsdl3demo
```

M1 的 2D 模式可用 SDL `dummy` 与软件渲染器冒烟测试。

```sh
zig build -Ddemo-2d=true --prefix zig-out/2d
timeout --preserve-status --kill-after=2s 3s env \
  SDL_VIDEODRIVER=dummy SDL_RENDER_DRIVER=software \
  ./zig-out/2d/bin/zigsdl3demo
```

### 里程碑验证记录

| 里程碑 | 交付与验证记录 |
| --- | --- |
| M0 项目骨架 | 锁定 Zig 与依赖，建立构建、日志和分配器基础 |
| M1 SDL 平台 | 2D 模式验证窗口、键鼠输入和尺寸事件 |
| M2 GPU 基础 | 虚拟显示下窗口中心清屏色为 RGB (26, 51, 102)，缩放后提交尺寸随窗口更新 |
| M3 基础渲染 | 虚拟显示下确认纹理立方体旋转、ImGui 数据、缩放和自由飞行输入 |
| M4 Scene / ECS | 确认父子模型绕行、Render Queue 与窗口缩放后持续绘制 |
| M5 资产 | 确认内嵌/外部 GLB、相对路径 PNG/JPEG、base64 数据和缓存命中，缺失外部缓冲区返回 `FileNotFound` |
| M6 光照 | 软件 Vulkan 下确认阴影移动、透明裁剪投影、法线贴图、天空转向和缩放 |
| M7 物理 | Xvfb / Lavapipe 验证刚体落地并停稳、射线命中地面及法线，独立物理测试通过 |
| M8 角色 | Xvfb / Lavapipe 验证走、跑、跳、碰墙停止与落地 |
| M9 武器 | Xvfb / Lavapipe 验证伤害、击倒、三种命中标记、空弹匣和换弹 |
| M10 HUD / 音效 | 验证 HUD 随窗口缩放，释放鼠标隐藏准星。隔离 ALSA 输出捕获 7 次开火声，其中 5 次有额外命中音 |
| M11 Demo / Hardening | Blender 场地、机器人状态机与路点、胜负结算与重开、ReleaseSafe 发布构建及 [Tracy 采样](docs/M11_Performance.md) |

默认 Debug、ReleaseSafe、2D 和清屏配置均通过构建与测试。交互与音频记录来自 Linux 虚拟显示、软件 Vulkan 与隔离音频输出。实体 GPU、真实桌面窗口管理器和物理播放设备尚待实机验证。发布标签以 `git tag --list` 为准。

## 常见问题

| 现象 | 排查方法 |
| --- | --- |
| 构建提示需要 Zig 0.17.1 | 用 `zig version` 确认当前 shell 找到的 Zig 版本，以及 `PATH` 中是否存在另一个安装 |
| 首次构建拉取依赖失败 | 检查 GitHub 访问和代理配置，恢复连接后重跑构建。下载地址和预期内容哈希在 `build.zig.zon` 中 |
| Vulkan 设备创建失败 | 检查 Vulkan loader、ICD 和 SDL 视频后端。可先运行清屏模式隔离图形问题，或使用上面的 Lavapipe 示例 |
| 加载外部模型报 `FileNotFound` | 确认 `.bin` 和纹理文件相对于模型文件的位置与 glTF 中的 URI 一致 |
| 纹理缺失或出现 `UnsupportedTextureCoordinates` | 将材质纹理导出到 UV0，去掉纹理坐标变换，并导出为 PNG/JPEG |
| 默认训练场无声 | 查看启动日志中的 `audio` 行，检查系统默认播放设备及静音状态。音频初始化失败时，Demo 会记录警告并继续运行 |
| 修改 HLSL 后画面仍旧 | 安装启用了 DXC 的 shadercross，按着色器开发章节生成并更新对应 SPIR-V |
