# Research: 游戏大厅界面

**日期**：2026-11-26
**方法**：`explorer` 对 `main.zig`、`demo_scene.zig`、`imgui_bridge.cpp`、`input.zig`、`camera.zig`、音频桥接与 `build.zig` 做只读 recon（精确到行号）；`designer` 出大厅 UI/UX 设计；结合 spec.md 已澄清条目与 README 验收记录。决策需满足宪章（Zig 0.17.1 锁定、依赖不新增、2D/清屏独立构建、零回归）。

## 现状结论（explorer recon）

| 主题 | 发现 |
| --- | --- |
| 模式选择 | `src/main.zig:8-10` 由 `demo-2d` / `clear-only` 构建标志决定；`main.zig:29-38` 按标志选 Vulkan/2D 窗口；`main.zig:40-48` 分别初始化 SDL Renderer 2D、`GpuRenderer` 清屏或 `DemoScene`（默认/GLB）。**没有可复用的「进入/退出模式」抽象**。 |
| 事件循环 | `main.zig:81-162`；`.quit`/`.close_requested`（:91,:95）与 Esc（:116）都直接 `break :loop` 退出程序。窗口 resize（:96-99）、最小化跳过渲染（:125-128）。 |
| 场景生命周期 | `DemoScene.init` `demo_scene.zig:135` 加载 GLB、Jolt、ImGui、Audio、管线；`DemoScene.deinit` `demo_scene.zig:216` 释放。2D/清屏各自在 `main.zig:47` 调 `renderer.deinit()`。 |
| ImGui | `imgui_bridge.cpp:1-26` `demo_imgui_init/shutdown/event`；`:35-38` 事件转发；`:55-135` `draw_hud`；`:137-179` `demo_imgui_prepare`；`:181-184` `demo_imgui_draw`。可共用同一上下文。**默认字体仅 ASCII，未加载中文字形**。 |
| 输入 | `input.zig:34-51` `InputState`；`:84-107` `handleEvent`；`:126-137` 相对鼠标模式；`:140-153` scancode→Action（WASD/Space/Shift/Ctrl/R/E）。Esc 不映射到 Action，在 `main.zig:116` 单点读取。 |
| 灵敏度 | `camera.zig:34` 硬编码 `0.0025` rad/px（`look`）；无灵敏度的设置入口。 |
| 音量 | `miniaudio_bridge.c:70-102` `demo_audio_create` 无音量控制；`demo_audio.zig` 仅暴露 create/destroy/play_shot。 |
| resize | `main.zig:96-99` 记录尺寸；`demo_scene.zig:357-392` 各 pass 使用当前 frame extent，交换链变更自动适配。 |
| 构建约束 | `build.zig:53` `if (!demo_2d and !clear_only)` 守护 Jolt/资产/miniaudio/ImGui；`build.zig:84-99` ImGui 条件编译。**2D/清屏必须继续跳过这些模块**。 |

## R1 — 大厅与四模式如何共存（决策）

**Decision**：在大厅模式下引入一个轻量运行时状态机（新建 `src/engine/gameplay/lobby.zig`，或放在 `src/engine/gameplay/` 下的独立模块），由它持有 `LobbySession` 状态；`main.zig` 的顶层循环改为：默认构建时先进入大厅，选择模式后再调用既有的 `DemoScene.init` / 2D `draw()` / `renderer.clear()` 逻辑，返回大厅时调用对应的 `deinit`。保留 `-Ddemo-2d=true` / `-Dclear-only=true` 作为独立构建入口（测试门禁仍按原命令运行），但在这些构建中也允许模式内 Esc 返回大厅（若其构建中不含 ImGui，则大厅 UI 需走无 ImGui 的最小绘制路径——见 R2）。

**Rationale**：避免为四种模式重复实现初始化/释放逻辑；`DemoScene.init/deinit` 已经是默认/GLB 模式的生命周期边界，大厅只需在它外包一层状态机，符合宪章 III「增量改动与零回归」。

**Alternatives considered**：把四种模式全部重写为统一运行时抽象（拒绝：改动面过大，破坏已验收的独立构建门禁）；新增第五种构建标志 `-Dlobby`（拒绝：会让大厅脱离默认构建，SC-001 的「启动即大厅」不成立）。

## R2 — 大厅 UI 的绘制与中文字体（决策）

**Decision**：复用 `imgui_bridge.cpp` 的现有上下文，新增大厅绘制入口（与 `demo_imgui_prepare` 并列的 lobby 绘制函数），由 `LobbySession` 提供要显示的文本/数值；2D 与清屏构建沿用各自的轻量绘制路径，不引入 ImGui（保持 `build.zig:53` 守护不变）。中文字体：需在 ImGui 初始化时加载带中文 glyph 的 TTF（`imgui_bridge.cpp` 的 `demo_imgui_init` 附近），若仓库无合适字体资源，则把字体文件放入 `assets/` 并在 `build.zig.zon.paths` 中纳入；具体字体与回退策略见「R5 字体决策」。

**Rationale**：FR-009 要求所有可见文本中文；ImGui 默认字体只有 ASCII，不加载中文字体会直接违反验收。共用上下文避免第二套 UI 栈；2D/清屏保持无 ImGui 是硬性构建约束。

**Alternatives considered**：用 SDL 软件渲染自绘菜单（拒绝：重复实现输入/布局，且默认构建已有 ImGui）；仅用 ASCII/拼音文案（拒绝：违反 FR-009）。

## R3 — Esc 与退出语义（决策）

**Decision**：把 `main.zig:116` 的 Esc 分支从「一律 break」改为「按当前 `LobbySession.当前界面` 分派」：非大厅模式 → 返回大厅并释放该模式资源；大厅 → 忽略 Esc。程序退出只由大厅「退出」按钮和 `.quit`/`.close_requested` 事件触发（后者原有逻辑保留）。

**Rationale**：Esc 读取点唯一，改动集中且可验证（FR-008、Clarifications Session 2026-11-25 Q3）；保留窗口关闭退出，满足 Edge Cases。

**Alternatives considered**：在每个模式内部各自处理 Esc（拒绝：重复逻辑、易遗漏，且 `main.zig` 仍会 break）；把 Esc 映射为 `InputState.Action`（拒绝：需要改动 `input.zig` 的通用映射，影响全部模式）。

## R4 — 设置接入（决策）

**Decision**：
- 视角灵敏度：在 `camera.zig` 的 `Camera` 增加 `sensitivity: f32`，默认值沿用现行 `0.0025`（对应 UI 默认 1.0 倍），`look` 中用 `delta.x * sensitivity` 替换硬编码；进入场景时由 `LobbySession.会话设置.视角灵敏度` 换算注入（1.0→0.0025）。
- 音量：在 `miniaudio_bridge.c`/`demo_audio.zig` 增加 `demo_audio_set_volume(engine, volume)` 包装，把 0–100 映射为 0.0–1.0；进入含音效场景时应用，仅会话内有效（FR-007）。非法值收敛与提示由大厅 UI 负责，非法值不进入场景。

**Rationale**：仅新增必要参数接口，不改变相机/音频既有默认值与玩法；满足「最小源码适配」边界（FR-011、宪章 V）。

**Alternatives considered**：全局可变设置单例（拒绝：引入隐式状态，违背确定性状态原则）；持久化到配置文件（拒绝：Assumptions 明确本版本不持久化）。

## R5 — 字体决策

**Decision**：随仓库内置一份带简体中文 glyph 的 TTF（designer 选定 Noto Sans SC，OFL 许可，Regular + Bold 子集），放入 `assets/` 并纳入 `build.zig.zon.paths`；在 `imgui_bridge.cpp` 的 `demo_imgui_init` 中用 `ImGui::GetIO().Fonts->AddFontFromFileTTF(...)` 加载。系统 CJK 字体（验收机有 Noto Sans CJK / Droid Sans Fallback）仅作次级兜底，不进入正常路径。字体按 DPI 档预生成图集，禁止每帧重建（Lavapipe 性能约束）。因为字体随构建发布，运行时不依赖系统字体、不新增外部依赖，满足宪章 I 的离线可复现构建。

**Rationale**：`assets/` 当前只有 GLB 与导出脚本，ImGui 默认字体仅 ASCII；FR-009 要求所有可见文本中文，因此中文字体是必需资源而非可选增强。designer 的 564 行 `ui-design.md`（`specs/001-game-lobby-ui/ui-design.md`）给出完整布局、文案、状态矩阵与 D-01–D-18 验收点，是本决策的设计依据。

**Alternatives considered**：（1）运行时引用系统字体路径——拒绝：破坏离线/跨环境可复现，且路径不固定；（2）正常路径用英文标签——拒绝：直接违反 FR-009；（3）用 SDL 自绘文本——拒绝：重复实现文本渲染栈，且无法复用现有 ImGui UI。

**Fallback 边界**：内置与系统 CJK 字体**均**不可用这一异常路径下，designer 建议进入 ASCII 可读降级界面（`UI FONT UNAVAILABLE` + `Exit`）并写日志；该界面仅用于资源彻底失效时避免空白/豆腐块，**不属于正常验收范围**，正常路径必须是全中文（FR-009）。不得在正常路径静默降级为英文。

**设计补充**：布局按 designer 的断点方案实现：宽屏 ≥1080 双栏（左 58% 主入口 + 设置，右 42% 次级模式 + 错误横幅）；中屏 720–1079（含默认 800×600）单栏首屏完整；窄屏 <720 纵向堆叠、内容可滚动、页脚固定。主入口「开始训练」为唯一高视觉权重焦点，「退出」独立右置。Esc 采用 designer 的优先级矩阵（编辑态撤销 → 关横幅 → 返回大厅/预览 → 空操作），且**永不退出程序**；连续快速确认按 spec Edge Cases 取**最后确认**的模式，只初始化一次（designer 原稿的“先确认者生效”已按 spec 修正）。完整文案清单见 `ui-design.md` 第 4 节与 `contracts/lobby-ui.md`。E2E 验证在默认构建中进行，`-Ddemo-2d=true` / `-Dclear-only=true` 保持独立构建入口（`research.md` R1）。

## R6 — 验证与不变量（决策）

**Decision**：以 `contracts/acceptance-gates.md` 的 G1–G5 与 `quickstart.md` 的 V1–V6 为唯一判定；构建图改动不得破坏 `build.zig:53` 守护，2D/清屏仍独立构建测试；默认训练场启动日志必须出现 `缓存命中 embedded:demo.glb`；物理步长 1/60s、每帧最多 6 步、相机 1.6m、最近碰撞射线、HLSL/SPIR-V 同步均不变。

**Rationale**：宪章 II/III/IV 与 FR-011；任何不变量漂移都会让既有 M0–M11 验收结论失效。

**Alternatives considered**：为大厅调整物理或渲染参数（拒绝：直接违反 FR-010/FR-011）。

## 未解决项

- 无。designer 的 `ui-design.md` 已返回并一致化：布局断点、文案清单、Esc 矩阵与 D-01–D-18 验收点已并入 `contracts/lobby-ui.md` 与 `quickstart.md`；其“先确认者生效”已按 spec Edge Cases 改为“最后确认者生效”，ASCII 降级限定为字体全失效的异常兜底。Technical Context 无 `NEEDS CLARIFICATION`。
