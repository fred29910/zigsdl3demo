# Bug Assessment: 返回大厅后交换链 surface 丢失导致获取帧失败

- **Slug**: lobby-mode-switch-crash
- **Created**: 2026-11-26
- **Source**: pasted text（用户「修复按钮测试」日志）
- **Verdict**: likely valid, needs reproduction
- **Severity**: high

## Report (verbatim or summarized)

```
修复按钮测试，报错[INFO] lobby: 返回大厅
wl_display#1: error 1: invalid arguments for wp_fifo_manager_v1#58.get_fifo
[ERROR] gpu: 获取交换链图像失败: vkGetPhysicalDeviceSurfaceFormatsKHR VK_ERROR_SURFACE_LOST_KHR
```

无 URL。日志来自真实 Wayland 桌面会话（`wl_display#1`），不是本仓库此前使用的 Xvfb/X11 验收基线。`[INFO] lobby: 返回大厅` 由 `src/main.zig:139` 的 Esc 分支打印，说明触发点是「模式内按 Esc 返回大厅」，而非预览 UI 的「返回大厅」按钮（该按钮走 `src/main.zig:189`，不打印此日志）。

## Symptom

在模式内按 Esc 返回大厅后，Wayland 合成器报告 `wp_fifo_manager_v1.get_fifo` 参数非法，紧接着 SDL GPU 获取交换链图像失败，SDL 的最后错误文本为 `vkGetPhysicalDeviceSurfaceFormatsKHR VK_ERROR_SURFACE_LOST_KHR`。预期行为是返回大厅后继续正常渲染大厅 UI，不产生协议错误、不中断帧循环。

## Reproduction

1. 在广告 `wp_fifo_manager_v1` 的 Wayland 合成器会话中运行 `zig build run`（默认大厅构建）。
2. 进入外部模型预览（Tab ×1 + Return），在「模型路径」填有效 GLB，点「加载模型」进入 viewer 模式。
3. 按 Esc 从 viewer 返回大厅（会打印 `[INFO] lobby: 返回大厅`）。
4. 观察后续日志出现 `wp_fifo_manager_v1 … get_fifo` 协议错误与 `VK_ERROR_SURFACE_LOST_KHR`；帧循环随后以错误退出（`main.zig:238` 的 `try` 会把 `scene.render` 的错误传播出 `main`）。
5. [NEEDS CLARIFICATION: 合成器名称/版本、SDL_VIDEO_DRIVER 实际取值（wayland 还是 x11）、是否每次返回大厅都复现、进程是退出还是继续黑帧。]

## Suspected Code Paths

- `src/main.zig:131-139` — viewer 模式 Esc 分支：`scene.deinit()` 后立即 `DemoScene.init(..., null)`，再 `lobby.returnToLobby`；这是唯一打印「返回大厅」的路径，且与报错时序吻合。
- `src/main.zig:174-181` — 预览界面点「加载模型」时同样做 `scene.deinit()` + `DemoScene.init(path)`，属于同类 GPU 后端重建。
- `src/engine/renderer/demo_scene.zig:178` — `init` 调用 `device.swapchainTextureFormat(renderer.window)`，触发交换链/surface 格式查询。
- `src/engine/renderer/demo_scene.zig:187,230` — `init` 调 `demo_imgui_init`、`deinit` 调 `demo_imgui_shutdown`，每次模式切换都完整销毁/重建 ImGui + SDL GPU 后端。
- `src/engine/renderer/demo_scene.zig:227` — `deinit` 中 `device.waitForIdle()`，与 `gpu_renderer.zig:64` 的 `waitForIdle()` 叠加，构建期间存在多帧在途资源。
- `src/engine/renderer/imgui_bridge.cpp:7-27` — `demo_imgui_init` 重新 `ImGui::CreateContext()`、`ImGui_ImplSDL3_InitForSDLGPU(window)`，并调用 `SDL_GetGPUSwapchainTextureFormat(device, window)`（第 19 行）；ImGui Vulkan 后端自身也会调用 `vkGetPhysicalDeviceSurfaceFormatsKHR`。
- `src/engine/renderer/imgui_bridge.cpp:29-34` — `demo_imgui_shutdown` 完整销毁上下文。
- `src/engine/renderer/gpu_renderer.zig:72-90` — `acquireFrame` 把 `waitAndAcquireSwapchainTexture` 的失败当作致命错误：第 78 行打印 `sdl.lastErrorText()`，第 79 行 `cancel` 后第 80 行 `return err`。
- `src/main.zig:237-240` — `try scene.render(...)` / `try renderer.clear()` 把该错误直接传播出 `main`，导致进程退出；没有「跳过本帧、下帧重试」的恢复路径。
- SDL 依赖（非本仓库源码）：`zig-pkg/sdl-0.6.1+…/src/gpu/vulkan/SDL_gpu_vulkan.c:10218-10220` 在 `vkAcquireNextImageKHR` 返回 `VK_ERROR_SURFACE_LOST_KHR` 时置 `needsSurfaceRecreate`/`needsSwapchainRecreate`；同文件 `:10137-10153` 在下次获取时销毁并重建 `VkSurfaceKHR`；`:4505-4550` 的格式查询失败会把 `vkGetPhysicalDeviceSurfaceFormatsKHR …` 写入 SDL 最后错误文本。`src/video/wayland/SDL_waylandvideo.c:499-546` 显示 SDL 在 Wayland 上依赖 `wp_fifo_manager_v1`，否则回退 XWayland。

## Root Cause Hypothesis

模式切换（尤其是 viewer → 大厅的 Esc 返回）会完整销毁并重建 `DemoScene`，连带 `ImGui` 上下文和 SDL GPU 后端的 surface 相关状态：`src/main.zig:132-133` → `demo_scene.zig:187/230` → `imgui_bridge.cpp:19`，其中 `SDL_GetGPUSwapchainTextureFormat` / ImGui Vulkan 后端会重新查询 `vkGetPhysicalDeviceSurfaceFormatsKHR`。在广告 `wp_fifo_manager_v1` 的 Wayland 合成器上，这次重建与 SDL 的 fifo/surface 生命周期发生竞争，出现 `get_fifo` 协议参数错误，随后 `VkSurfaceKHR` 失效。下一次 `waitAndAcquireSwapchainTexture` 失败，SDL 尝试恢复时再次查询 surface 格式也返回 `VK_ERROR_SURFACE_LOST_KHR`，该文本被 `gpu_renderer.zig:78` 打印；由于 `main.zig:238` 用 `try` 传播错误，瞬时的 surface 丢失被当作致命错误，帧循环终止。次要因素是：本应在后续帧由 SDL 的 `needsSurfaceRecreate` 自动恢复的瞬时错误，没有被当作「跳过一帧」处理。补充证据：`GpuRenderer.deinit()` 仅在程序退出时经 `src/main.zig:48` 的 `defer` 调用，返回大厅不销毁窗口、GPU 设备或交换链本身；而 `lobby.returnToLobby`（`src/engine/gameplay/lobby.zig:44-48`）只改会话状态、不触碰渲染资源。因此 surface 丢失不是应用直接销毁窗口造成的，而是 SDL Wayland 后端在场景重建期间的 fifo/在途呈现状态未正确重同步（`DemoScene.deinit` 的 `device.waitForIdle()` 只保证 Vulkan 设备空闲，未覆盖 `wp_fifo_manager_v1` 的在途呈现队列）。另一个并列候选是 ImGui 以过期交换链格式初始化（`demo_scene.zig:178` + `imgui_bridge.cpp:19`），使后续 `renderLobby` 的命令缓冲/渲染通道布局不匹配。置信度：medium（日志时序与本仓库代码链吻合，但缺少在有 fifo-v1 的真实 Wayland 合成器上的本地复现，无法确认协议错误与 surface 丢失的因果方向）。

## Proposed Remediation

**Preferred**（两部分，最小改动）：

1. 消除模式切换时的 GPU 后端重建。给 `DemoScene` 增加 `reloadModel(path: ?[]const u8)`，只重建模型/资产/实体/管线等随模型变化的部分，保留 ImGui 上下文与 swapchain 侧状态；`demo_imgui_init` / `demo_imgui_shutdown` 仍只在整个程序生命周期首尾各调用一次。把 `src/main.zig:132-133`（viewer → 大厅）与 `:174-175`（预览加载模型）的 `scene.deinit(); scene = DemoScene.init(...)` 改为 `try scene.reloadModel(...)`。这样「返回大厅」不再触发 `SDL_GetGPUSwapchainTextureFormat` / surface 格式重查，直接消除报错时序中的重建动作。必须保持 `缓存命中 embedded:demo.glb` 验收不回归。

2. 把瞬时交换链错误改为可恢复。`GpuRenderer.acquireFrame`（`src/engine/renderer/gpu_renderer.zig:72-90`）对 `VK_ERROR_SURFACE_LOST_KHR` / `VK_ERROR_OUT_OF_DATE_KHR` / `VK_SUBOPTIMAL_KHR` 对应的 SDL 错误，在 `cancel(commands)` 后返回 `null`（跳过本帧）并以 warn 记录，而不是 `return err`；其他错误仍保持致命。这样即使合成器导致瞬时 surface 丢失，SDL 的 `needsSurfaceRecreate/needsSwapchainRecreate` 也能在下一帧生效，而不是让 `main.zig:238` 把错误传播出 `main` 结束进程。建议把错误分类抽成可单测的纯函数（如 `isTransientSwapchainError`）。

**Alternatives**：
- 文档/环境规避：在 README 注明可设置 `SDL_VIDEO_DRIVER=x11` 走 XWayland 绕过 wlroots fifo-v1 问题。成本低，但改变渲染路径，且不修复应用自身的脆弱性。
- 调整 `src/main.zig:30-34` 的 `.maximized = true` / `.high_pixel_density = true` 以减少 Wayland 下的 surface 尺寸变更。属 UX 取舍且因果不确定，不推荐作为主修复。
- 显式 `SDL_ReleaseWindowFromDevice` / 重新绑定窗口。风险较高，除非证明与 fifo 协议错误直接相关，否则不采用。

**Files likely to change**：
- `src/main.zig`
- `src/engine/renderer/demo_scene.zig`
- `src/engine/renderer/gpu_renderer.zig`
- `src/engine/renderer/imgui_bridge.cpp`（若需要给 `SDL_GetGPUSwapchainTextureFormat` 失败加重试/保护）
- `specs/001-game-lobby-ui/quickstart.md`（增加回归场景，见下）

**Tests to add or update**：
- 在 `src/engine/renderer/gpu_renderer.zig` 的测试块（或新纯函数测试）中覆盖 `isTransientSwapchainError`：surface-lost/out-of-date/suboptimal 为 true，其他错误为 false。
- 端到端回归（真实 Wayland 桌面）：`zig build run` → 预览加载有效 GLB → 连续 5 次 Esc 返回大厅并再次进入；断言进程存活、无 `[ERROR] gpu:` 行、无 `wp_fifo_manager_v1` 协议错误。
- 保持 G1–G5（`zig build install test` 及 ReleaseSafe / physics / 2D / clear-only）全绿；`models` 缓存语义不回归。

## Risks & Considerations

- `reloadModel` 必须保留内嵌 GLB 的共享缓存语义，否则会破坏既有验收项 `缓存命中 embedded:demo.glb`。
- ImGui 是全局单例上下文，`reloadModel` 绝不能调用 `demo_imgui_shutdown/init`，否则会重复创建/销毁上下文。
- 把瞬时错误改为跳帧可能掩盖真实 GPU 故障；仅对明确的 surface-lost/out-of-date 子类生效，其他错误仍致命，并保留 warn 日志便于观测。
- `wp_fifo_manager_v1.get_fifo` 的协议错误可能源自 SDL/Wayland 合成器实现本身；应用侧修复可消除触发条件并提高健壮性，但未必能彻底消除协议错误，需要在真实 Wayland 上复验。
- 当前环境只有 Xvfb/X11，本 bug 的原始日志来自 Wayland 桌面，本地无法完整复现；修复后仍需用户在真实桌面确认。

## Open Questions

- [NEEDS CLARIFICATION: Wayland 合成器与版本、SDL_VIDEO_DRIVER 实际取值，以及是否每次从 viewer 按 Esc 都复现。]
- [NEEDS CLARIFICATION: 出现错误后进程是立即退出，还是继续运行但画面冻结/黑屏？]
- [NEEDS CLARIFICATION: 报错时窗口是否处于 maximized + high_pixel_density（2880x1544 之类）状态？]
