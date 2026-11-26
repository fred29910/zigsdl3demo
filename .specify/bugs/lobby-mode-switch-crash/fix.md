# Bug Fix: 返回大厅后交换链 surface 丢失

- **Slug**: lobby-mode-switch-crash
- **Fixed**: 2026-11-26
- **Assessment**: ./assessment.md
- **Status**: partial

## Summary

按评估的 Preferred 方案实施了两项改动：`DemoScene.reloadModel` 事务式重建模型侧资源，不再在模式切换时重建 ImGui/GPU 后端；`GpuRenderer.acquireFrame` 把瞬时交换链错误降为 WARN 并跳帧。G1–G5 全绿。但本轮 Xvfb/Wayland 冒烟发现评估未覆盖的触发路径（demo_2d → 大厅），协议错误仍会复现并导致 Wayland 连接被合成器关闭，因此状态为 partial，需重新评估后补修。

## Changes

| File | Change | Notes |
|------|--------|-------|
| `src/engine/renderer/demo_scene.zig` | modified | 新增 `allocator` 字段与事务式 `reloadModel`；保留 ImGui 上下文、管线、环境与设备/窗口状态；`init` 行为不变，`deinit` 仍只调用一次 `demo_imgui_shutdown` |
| `src/main.zig` | modified | viewer Esc 返回与预览加载模型两处 `scene.deinit()+init` 改为 `scene.reloadModel(init.io, ...)`；失败时保留旧场景、给出可读提示、不退出 |
| `src/engine/renderer/gpu_renderer.zig` | modified | 新增 `isTransientSwapchainError` 纯函数与 5 项单测；获取交换链图像前 `sdl.clearError()`；在 `cancel` 前分类错误文本；瞬时错误 WARN + `return null` 跳帧，其余错误仍致命 |
| `specs/001-game-lobby-ui/quickstart.md` | modified | 新增 V7「返回大厅稳定性回归」场景（真实 Wayland 桌面，5 次切换断言） |

## Diff Highlights (optional)

```zig
// demo_scene.zig — 事务式：先建新资源，全部成功后才释放旧资源
pub fn reloadModel(self: *DemoScene, io: std.Io, path: ?[]const u8) !void {
    var new_manager = try assets.AssetManager.init(self.allocator, self.device);
    errdefer new_manager.deinit();
    // ... model(含缓存命中) / registry / instance / training / audio 均在局部构建
    // 成功后才释放 self.audio / training / instance / registry / model / assets
}
```

```zig
// gpu_renderer.zig — 必须在 cancel 前读取并分类（cancel 会覆盖 SDL 错误文本）
const message = sdl.lastErrorText();
if (isTransientSwapchainError(message)) {
    log.log(.warn, "gpu", "交换链暂时不可用，跳过本帧: {s}", .{message});
    cancel(commands) catch {};
    return null;
}
```

## Tests Added or Updated

- `src/engine/renderer/gpu_renderer.zig::isTransientSwapchainError` — 3 个 true（surface-lost / out-of-date / suboptimal）+ 2 个 false（普通错误、空串），锁定错误文本分类规则。
- `specs/001-game-lobby-ui/quickstart.md::V7` — 真实 Wayland 桌面上连续 5 次返回大厅/再进入，断言进程存活、无协议错误、无 `[ERROR] gpu:`、缓存命中语义不回归。

## Local Verification

- Commands run: `zig build install test` → 退出码 0；`zig build install test -Doptimize=ReleaseSafe` → 0；`zig build physics-test` → 0；`zig build test -Ddemo-2d=true` → 0；`zig build test -Dclear-only=true` → 0。
- Manual checks: Xvfb + XTest（`WAYLAND_DISPLAY=wayland-0`，SDL 实际走 Wayland）验证大厅 Esc 不退出、训练场 Esc 返回、二次 Esc 不退出；`缓存命中 embedded:demo.glb` 保持出现。
- **新证据**：进入 demo_2d 模式后按 Esc 返回大厅时，仍出现
  `wl_display#1: error 1: invalid arguments for wp_fifo_manager_v1#73.get_fifo`，
  随后 `[WARN] gpu: 交换链暂时不可用，跳过本帧: vkGetPhysicalDeviceSurfaceFormatsKHR VK_ERROR_SURFACE_LOST_KHR`，
  再随后 `ERROR: Wayland display connection closed by server (fatal)` 并退出。
  说明跳帧处理生效（gpu 错误已降为 WARN），但没有消除协议错误本身；该路径未调用 `reloadModel`。

## Deviations from Assessment

- 评估把 surface 丢失归因于 viewer → 大厅的 `scene.deinit()` + `DemoScene.init()`（ImGui/GPU 后端重建）。该修复已实施，但本轮复现来自另一条路径：默认构建进入 **demo_2d** 模式后按 Esc 返回大厅。该路径只调用 `lobby.returnToLobby`，不调用 `reloadModel`。
- 新证据指向未覆盖的根因候选：`src/main.zig:213-214` 在同一个窗口上创建软件 `SDL_Renderer`（`renderer_2d`），离开 demo_2d 模式时从未销毁，GPU 设备与软件渲染器同时持有同一 Wayland surface，可能是 `wp_fifo_manager_v1.get_fifo` 参数非法的直接触发条件。评估的「Files likely to change」未包含该生命周期问题。
- 由于发现评估未覆盖的根因，按 `/speckit.bug.fix` 约束停止继续改动代码；两项已实施改动保留（它们消除了 viewer 路径的后端重建，并把致命 gpu 错误降为可恢复跳帧），但不足以解决新发现的触发路径。

## Follow-ups

- 重新运行 `/speckit.bug.assess slug=lobby-mode-switch-crash`，把 demo_2d → 大厅的复现证据纳入；预期补充修复是在离开 demo_2d 时销毁 `renderer_2d`（`main.zig`，本评估已在文件范围内）并避免同一窗口被 GPU 设备与软件渲染器同时持有。
- 改动尚未提交；重新评估并补修后统一提交，提交信息沿用中文 `fix:` 前缀。
- 真实 Wayland 桌面仍需按 `quickstart.md` V7 做 5 次切换复核；当前 Xvfb 环境虽走 Wayland，但输入焦点不稳定，无法覆盖 viewer 预览路径。
