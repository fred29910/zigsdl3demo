# Bug Assessment: 返回大厅后交换链 surface 丢失（demo_2d 路径已复现）

- **Slug**: lobby-mode-switch-crash
- **Created**: 2026-11-26（重新评估，覆盖 2026-11-26 首版）
- **Source**: pasted text（用户「修复按钮测试」日志）+ 本地 Xvfb/Wayland 复现
- **Verdict**: valid
- **Severity**: high

## Report (verbatim or summarized)

用户原始日志：

```
修复按钮测试，报错[INFO] lobby: 返回大厅
wl_display#1: error 1: invalid arguments for wp_fifo_manager_v1#58.get_fifo
[ERROR] gpu: 获取交换链图像失败: vkGetPhysicalDeviceSurfaceFormatsKHR VK_ERROR_SURFACE_LOST_KHR
```

本轮本地复现日志（`/tmp/opencode/fix-smoke.log`，环境 `WAYLAND_DISPLAY=wayland-0`、`XDG_SESSION_TYPE=wayland`，SDL 实际走 Wayland）：

```
[INFO] lobby: 进入模式: demo_2d
[INFO] lobby: 返回大厅
wl_display#1: error 1: invalid arguments for wp_fifo_manager_v1#73.get_fifo
[WARN] gpu: 交换链暂时不可用，跳过本帧: vkGetPhysicalDeviceSurfaceFormatsKHR VK_ERROR_SURFACE_LOST_KHR
ERROR: Wayland display connection closed by server (fatal)
[INFO] demo: 退出
```

无 URL。首版评估把触发点归于 viewer → 大厅的 `DemoScene` 重建；本地复现证明**至少还存在一条覆盖不到的路径：demo_2d → 大厅**。上一轮 fix（`reloadModel` + 瞬时错误跳帧）已让 gpu 错误降为 WARN，但协议错误与合成器关闭连接仍导致进程退出。

## Symptom

在默认构建的大厅中进入「2D 输入演示」后按 Esc 返回大厅，Wayland 合成器报告 `wp_fifo_manager_v1.get_fifo` 参数非法，随后 SDL GPU 获取交换链图像失败（surface 丢失），最终合成器关闭 Wayland 连接、进程退出。预期：返回大厅后继续正常渲染大厅 UI，不产生协议错误、不退出。

## Reproduction

1. 在有 `wp_fifo_manager_v1` 的 Wayland 会话中 `zig build run`（本轮为 Xvfb + `WAYLAND_DISPLAY=wayland-0`，SDL 3 优先选 Wayland）。
2. 在大厅用 Tab/点击选中「2D 输入演示」并确认（本轮 XTest 为 `Tab` + `Return`；按钮顺序见 `imgui_bridge.cpp:241-245`，2D 为第 3 个按钮，action=3）。
3. 按 Esc 从 demo_2d 返回大厅（日志打印 `[INFO] lobby: 返回大厅`）。
4. 观察到 `wp_fifo_manager_v1 … get_fifo` 协议错误、`VK_ERROR_SURFACE_LOST_KHR`，以及 `Wayland display connection closed by server (fatal)` 后退出。
5. 对照：大厅 Esc、训练场 Esc→大厅、二次大厅 Esc 均无此错误。说明问题特定于「软件渲染器工作过的窗口切回 GPU 渲染」这一路径。
6. [NEEDS CLARIFICATION: 用户原始日志对应的具体模式是否也是 demo_2d；Wayland 合成器名称与版本。]

## Suspected Code Paths

- `src/main.zig:30-38` — 窗口以 `.vulkan = !demo_2d` 创建；默认构建下为 `true`，即窗口始终带 Vulkan 能力。
- `src/main.zig:47`（`GpuRenderer.init`）与 `gpu_renderer.zig:47` — `device.claimWindow(window)` 让 GPU 设备独占声明该窗口。
- `src/main.zig:61-62` — `renderer_2d` 延迟创建，仅在进程退出时 `defer ... r.deinit()`。
- `src/main.zig:213-214` — 进入 demo_2d 时在同一窗口上创建 `sdl.Renderer.init(window, "software")`。
- `src/main.zig:231-235` — demo_2d 模式下用软件渲染器绘制；GPU 设备此时仍持有窗口。
- `src/main.zig:126-140` — Esc 返回大厅时只对非 viewer 模式调用 `lobby.returnToLobby`，**从不销毁 `renderer_2d`**；切回 `renderLobby` 后 GPU 与软件渲染器同时持有同一 Wayland surface。
- `src/engine/renderer/gpu_renderer.zig:72-91` — `acquireFrame` 是切回大厅后第一个 GPU 获取点；上一轮 fix 已把瞬时错误降为 WARN 跳帧，但无法阻止合成器因协议错误关闭连接。
- SDL 内部（非本仓库）：`zig-pkg/sdl-0.6.1+…/src/video/wayland/SDL_waylandvideo.c:499-546` 表明 SDL 在 Wayland 上依赖 `wp_fifo_manager_v1`，否则回退 XWayland；`src/gpu/vulkan/SDL_gpu_vulkan.c:10218-10220` 在 surface 丢失时置重建标志，`:4505-4550` 的格式查询失败会写入 SDL 最后错误文本。

## Root Cause Hypothesis

默认构建中，同一个 `SDL_Window` 先被 Vulkan GPU 设备 `claimWindow`（`main.zig:47` / `gpu_renderer.zig:47`），进入 demo_2d 时又在该窗口上创建软件 `SDL_Renderer`（`main.zig:213-214`）；返回大厅时只改会话状态（`main.zig:138`），软件渲染器一直存活到进程退出（`main.zig:62`）。于是 GPU 交换链与软件渲染器同时拥有同一 Wayland surface。切回大厅的第一次 `acquireFrame` 时，SDL 的 Wayland 后端在 fifo/surface 状态不一致的情况下发出 `wp_fifo_manager_v1.get_fifo` 请求，合成器判定参数非法并关闭 display 连接；`VkSurfaceKHR` 随之失效，`vkGetPhysicalDeviceSurfaceFormatsKHR` 返回 `VK_ERROR_SURFACE_LOST_KHR`，最终进程退出。置信度：**high**（本地已按上述步骤稳定复现，且训练场往返无此错误，形成对照）。上一轮 fix 中的 `reloadModel` 与瞬时错误跳帧是有效加固，但都不触及该双渲染器生命周期问题，因此不足以修复。

## Proposed Remediation

**Preferred**：在 `src/main.zig` 中补上 demo_2d 渲染器的退出清理。离开 demo_2d 模式（Esc 返回大厅，以及从 demo_2d 直接切换到其他模式的任何路径）时调用 `renderer_2d.?.deinit()` 并把 `renderer_2d` 置 `null`；进入 demo_2d 时保留现有延迟创建逻辑，这样再次进入会重建软件渲染器。清理前按需 `renderer.device.waitForIdle()`，确保没有在途 GPU 帧仍引用窗口。这样任何时刻窗口只由一种渲染后端持有，从根源上避免 fifo/surface 状态冲突。保留上一轮已实施的两项加固（`reloadModel` 事务式重建、瞬时交换链错误 WARN 跳帧），它们分别覆盖 viewer 路径和瞬时故障恢复。

**Alternatives**：
- 默认构建不再使用软件渲染器，改为用 GPU 渲染器绘制 2D 演示；可彻底消除双后端，但改动较大，需新增 GPU 2D 绘制路径。
- 进入 demo_2d 时 `device.releaseWindow(window)`，退出时重新 `claimWindow` 并可能重建交换链；语义更重，且可能引入新的 surface 重建竞争，风险高于 Preferred。

**Files likely to change**：
- `src/main.zig`（主要：renderer_2d 退出清理）
- `src/engine/renderer/gpu_renderer.zig`（保留已有加固；必要时补充重建后的格式一致性检查）
- `specs/001-game-lobby-ui/quickstart.md`（V7 增加 demo_2d → 大厅必测路径）
- `.specify/bugs/lobby-mode-switch-crash/fix.md`（补修后更新状态）

**Tests to add or update**：
- 扩展 V7：真实 Wayland 下「demo_2d → Esc → 大厅 → 再次进入」至少 5 轮；断言进程存活、无 `wp_fifo_manager_v1` 错误、无 `Wayland display connection closed`、无 `[ERROR] gpu:`。
- 保留 `gpu_renderer.zig` 的 `isTransientSwapchainError` 单测；补一条「跳帧后下一帧可正常提交」的端到端观察（日志出现新的已提交帧）。
- G1–G5 全绿；`缓存命中 embedded:demo.glb` 不回归。

## Risks & Considerations

- 销毁 `renderer_2d` 时若仍有在途帧或鼠标捕获，可能触发 SDL 内部警告；需在清理前释放捕获并等待设备空闲。
- 再次进入 demo_2d 时会重建软件渲染器，需确认不会因此产生新的 fifo 协议错误（本轮复现只覆盖「退出时未销毁」，入口路径尚未单独验证）。
- 合成器行为可能有版本差异；修复后仍需在真实 Wayland 桌面按 V7 复核，并保留 Xvfb/Wayland 作为可复现基线。
- 上一轮 fix 已在未提交的工作区中；补修时应与之一并提交，避免历史割裂。

## Open Questions

- [NEEDS CLARIFICATION: 用户原始报错对应的模式是否也是 demo_2d（还是 viewer/训练场）；这决定本次修复是否完全覆盖原始场景。]
- [NEEDS CLARIFICATION: Wayland 合成器名称与版本（用于确认 get_fifo 协议错误是否为已知实现缺陷）。]
