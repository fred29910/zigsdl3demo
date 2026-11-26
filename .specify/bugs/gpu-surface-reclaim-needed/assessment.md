# Bug Assessment: 2D 模式切回 GPU 后必须重建 Vulkan surface（旧修复已证伪）

- **Slug**: gpu-surface-reclaim-needed
- **Created**: 2026-11-26
- **Source**: pasted text（用户原始日志）+ 两轮本地 Wayland 复现 + 两轮失败修复的实测证据
- **Verdict**: valid
- **Severity**: high

## Report (verbatim or summarized)

用户原始日志：

```
修复按钮测试，报错[INFO] lobby: 返回大厅
wl_display#1: error 1: invalid arguments for wp_fifo_manager_v1#58.get_fifo
[ERROR] gpu: 获取交换链图像失败: vkGetPhysicalDeviceSurfaceFormatsKHR VK_ERROR_SURFACE_LOST_KHR
```

复现环境：`WAYLAND_DISPLAY=wayland-0`、`XDG_SESSION_TYPE=wayland`，SDL 3 优先走 Wayland，合成器广告 `wp_fifo_manager_v1`。

上一轮修复后的复现日志（`/tmp/opencode/fix2-smoke.log`）：

```
[INFO] lobby: 进入模式: demo_2d
[INFO] lobby: 已释放 2D 渲染器
[INFO] lobby: 返回大厅
wl_display#1: error 1: invalid arguments for wp_fifo_manager_v1#70.get_fifo
[WARN] gpu: 交换链暂时不可用，跳过本帧: vkGetPhysicalDeviceSurfaceFormatsKHR VK_ERROR_SURFACE_LOST_KHR  （连续 12 次）
ERROR: Wayland display connection closed by server (fatal)
[INFO] demo: 退出
```

本评估不覆盖 `.specify/bugs/lobby-mode-switch-crash/assessment.md`（按其结论实施的「退出时销毁 renderer_2d」已被实测证伪）。

## Symptom

默认构建中，从大厅进入 demo_2d（软件 SDL_Renderer）再按 Esc 返回大厅时，Wayland 合成器报告 `wp_fifo_manager_v1.get_fifo` 参数非法，Vulkan surface 丢失，合成器随后关闭 display 连接并导致进程退出。预期是返回大厅后继续正常渲染大厅 UI。训练场↔大厅往返不触发此问题，形成对照。

## Reproduction

1. 在有 `wp_fifo_manager_v1` 的 Wayland 会话中运行 `zig build run`。
2. 在大厅用 Tab/点击选中「2D 输入演示」并确认（按钮顺序 `imgui_bridge.cpp:241-245`，2D 为 action=3）。
3. 按 Esc 返回大厅。
4. 观察到 `wp_fifo_manager_v1 … get_fifo` 协议错误、`VK_ERROR_SURFACE_LOST_KHR`、合成器关闭连接（`Wayland display connection closed by server (fatal)`）与进程退出。
5. 已验证无效的修复 A：viewer→大厅改为事务式 `reloadModel`（避开 ImGui/GPU 后端重建）——不触及 demo_2d 路径，仍复现。
6. 已验证无效的修复 B：离开 demo_2d 时 `renderer_2d.deinit()` 并置 null（日志 `已释放 2D 渲染器` 确认执行）——协议错误与 fatal 仍紧随其后。
7. [NEEDS CLARIFICATION: Wayland 合成器名称/版本；用户原始日志对应的模式是否也是 demo_2d。]

## Suspected Code Paths

- `src/main.zig:30-38` — 窗口以 `.vulkan = !demo_2d` 创建；默认构建下 Vulkan 能力始终开启。
- `src/main.zig:47` / `gpu_renderer.zig:47` — GPU 设备 `claimWindow(window)`，持有该窗口的 `VkSurfaceKHR` 与交换链。
- `src/main.zig:61-62,213-214` — `renderer_2d` 软件渲染器延迟创建在同一窗口上；`gpu_renderer.zig:63-69` 的 `releaseWindow` 在进程退出前从不调用。
- `src/main.zig:126-150`（本轮工作区）— Esc 离开 demo_2d 时已销毁软件渲染器，但没有重建 GPU surface/swapchain。
- `src/engine/renderer/gpu_renderer.zig:72-91` — 切回大厅后第一个 GPU 获取点；瞬时错误跳帧只能降低日志级别，无法恢复已被合成器关闭的 display 连接。
- SDL 内部证据：`zig-pkg/sdl-0.6.1+…/src/gpu/vulkan/SDL_gpu_vulkan.c:9992-10041` 的 `VULKAN_ReleaseWindow` 会 `VULKAN_INTERNAL_DestroySwapchain`（10022）+ `vkDestroySurfaceKHR`（10026-10030）；`:9937-9943` 的 `VULKAN_CLAIM_WINDOW` 通过 `Vulkan_CreateSurface` 重建 surface。Zig 绑定提供 `claimWindow`（`zig-pkg/sdl3-0.1.0-…/src/gpu.zig:913`）、`releaseWindow`（:919）、`setSwapchainParameters`（`gpu.zig:923`）。
- `imgui_bridge.cpp:7-27` — ImGui 后端持有 `SDL_GetGPUSwapchainTextureFormat` 结果；若重建后格式变化，管线与 ImGui 需要同步。

## Root Cause Hypothesis

软件 `SDL_Renderer` 在已被 GPU 设备 `claimWindow` 的窗口上工作时，改变了该窗口对应的 Wayland surface/fifo 关联；仅销毁软件渲染器（`fix2` 已验证）并不会让 GPU 侧旧的 `VkSurfaceKHR` / fifo 绑定恢复有效，因此切回大厅的第一次 `acquireFrame` 仍然拿到失效 surface，SDL 发出参数非法的 `get_fifo` 请求，合成器关闭连接。要恢复可用状态，必须让 SDL GPU 显式销毁并重建窗口的 surface 与交换链——即 `releaseWindow` + `claimWindow` + `setSwapchainParameters`，这正是 SDL 内部在 surface 失效时采用的路径。置信度：**medium-high**（销毁软件渲染器无效已被实测证明；release/claim 能重建 surface 有 SDL 源码支撑，但尚未实机验证能消除协议错误）。

## Proposed Remediation

**Preferred**：在 `src/main.zig` 中围绕 demo_2d 模式显式重建 GPU 窗口绑定。

- 进入 demo_2d 前：`renderer.device.waitForIdle()`，然后 `renderer.device.releaseWindow(window)`（SDL 会销毁交换链与 `VkSurfaceKHR`），再创建软件渲染器用于 2D 绘制。
- 离开 demo_2d 时：先销毁软件渲染器（现有逻辑），再 `renderer.device.claimWindow(window)` + `renderer.device.setSwapchainParameters(window, .sdr, .vsync)`；校验 `swapchainTextureFormat(window)` 是否与创建管线时一致，一致则继续，不一致则记录可读错误并返回大厅（避免用错格式继续渲染）。
- 失败路径：`claimWindow` 失败时不要结束进程，设置大厅 notice 并保留可重试状态。
- 保留上一轮已实施的两项加固（`reloadModel` 事务式重建、瞬时交换链错误 WARN 跳帧）。

**Alternatives**：
- 为 demo_2d 创建独立窗口（`.vulkan = false`），绘制与事件均指向该窗口，主 GPU 窗口保持隐藏不动。可彻底避免双后端共享 surface，但需要调整 `window_id` 事件过滤，改动更大。
- 默认构建改为用 SDL GPU 绘制 2D 演示，彻底不创建软件渲染器；代码量最大，但消除根因。
- 环境规避：设置 `SDL_VIDEO_DRIVER=x11` 走 XWayland 绕过 wlroots fifo-v1；不改应用逻辑，但改变渲染后端，且需在 README 记录，作为最后手段。

**Files likely to change**：
- `src/main.zig`
- `src/engine/renderer/gpu_renderer.zig`（可加一个 `releaseWindowFor2d` / `reclaimWindowFrom2d` 封装，集中 waitForIdle、错误日志与格式校验）
- `src/engine/renderer/demo_scene.zig`（若格式变化需要同步管线/ImGui）
- `specs/001-game-lobby-ui/quickstart.md`（V7 增加「GPU surface 重建」断言）
- `README.md`（若采用 XWayland 规避说明）

**Tests to add or update**：
- V7 扩展：Wayland 下「demo_2d → Esc → 大厅 → 再进入」至少 5 轮，断言进程存活、无 `wp_fifo_manager_v1` 错误、无 `Wayland display connection closed`、出现 surface 重建成功日志、`缓存命中 embedded:demo.glb` 不回归。
- 加一条「重建后首次 GPU 帧成功提交」的日志断言（例如新的 `已提交 … 帧`）。
- G1–G5 全绿；`-Ddemo-2d=true` / `-Dclear-only=true` 独立构建不受影响。

## Risks & Considerations

- `releaseWindow` 会销毁交换链与 surface，期间不能有任何在途 GPU 帧；必须 `waitForIdle()` 后再调用。
- 重新 `claimWindow` 后 `swapchainTextureFormat` 理论上可能变化；若不校验，ImGui 与管线会用错格式。
- 反复 release/claim 增加模式切换开销；需确认在 5 轮切换中无资源泄漏或累积。
- 即使重建 surface，协议错误也可能源自 SDL/Wayland 合成器实现缺陷；必须在真实 Wayland 桌面与当前 Xvfb/Wayland 基线双重复验。
- 上一轮 uncommitted 改动（main.zig / quickstart.md / fix.md）包含已被证伪的 `renderer_2d` 销毁逻辑；实施本方案时应保留其日志或按新方案调整，避免重复清理。

## Open Questions

- [NEEDS CLARIFICATION: 合成器名称与版本，用于确认 get_fifo 是否为已知实现缺陷。]
- [NEEDS CLARIFICATION: 是否允许改变 2D 演示实现方式（独立窗口 / GPU 绘制），若允许则可彻底消除双后端共享窗口。]
