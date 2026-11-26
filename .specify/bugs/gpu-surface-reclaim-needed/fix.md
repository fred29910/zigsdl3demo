# Bug Fix: 2D 模式切回 GPU 时重建 surface 与交换链

- **Slug**: gpu-surface-reclaim-needed
- **Fixed**: 2026-11-26
- **Assessment**: ./assessment.md
- **Status**: applied

## Summary

围绕 demo_2d 模式显式管理 GPU 窗口绑定：进入 2D 前 `releaseWindow`（SDL 销毁交换链与 `VkSurfaceKHR`），离开时先销毁软件渲染器再 `claimWindow` + `setSwapchainParameters` 重建 surface/交换链，并校验交换链格式未变。临时自动切换探针在真实 Wayland 会话中确认 release→2D→reclaim 全程无协议错误、无 fatal、进程正常退出；G1–G5 全绿。完整 5 轮 V7 仍需在有输入设备的真实桌面复核。

## Changes

| File | Change | Notes |
|------|--------|-------|
| `src/engine/renderer/gpu_renderer.zig` | modified | 新增 `color_format` 字段；新增 `releaseWindowFor2d()` / `reclaimWindowFrom2d()`，含 waitForIdle、claim/release、swapchain 参数恢复、格式一致性校验与中文日志 |
| `src/main.zig` | modified | 进入 demo_2d 前释放 GPU 窗口绑定；创建软件渲染器失败时立即恢复；离开 demo_2d 时销毁软件渲染器后重建 GPU surface/交换链，失败给出可读 notice 而不退出 |
| `specs/001-game-lobby-ui/quickstart.md` | modified | V7 标题改为本 bug slug，并加入 `已释放 GPU 窗口绑定` / `已重建 GPU surface 与交换链` / 新帧提交的断言 |

## Diff Highlights (optional)

```zig
// gpu_renderer.zig
pub fn releaseWindowFor2d(self: GpuRenderer) void {
    self.device.waitForIdle() catch { /* warn */ };
    self.device.releaseWindow(self.window); // SDL 销毁交换链 + VkSurfaceKHR
}

pub fn reclaimWindowFrom2d(self: GpuRenderer) !void {
    try self.device.claimWindow(self.window);
    errdefer self.device.releaseWindow(self.window);
    try self.device.setSwapchainParameters(self.window, .sdr, .vsync);
    if (self.device.swapchainTextureFormat(self.window) != self.color_format)
        return error.SwapchainFormatChanged;
}
```

```zig
// main.zig — 离开 demo_2d
if (renderer_2d) |r| { r.deinit(); renderer_2d = null; }
lobby.returnToLobby(&session);
renderer.reclaimWindowFrom2d() catch |err| {
    log.log(.error_, "gpu", "恢复 GPU 窗口绑定失败 ({s})", .{@errorName(err)});
    lobby.setNotice(&session, "恢复图形设备失败，请重试。");
};
```

## Tests Added or Updated

- `specs/001-game-lobby-ui/quickstart.md::V7` — Wayland 下 demo_2d→大厅 5 轮，断言无 `wp_fifo_manager_v1` 错误、无 fatal、有重建日志与新提交帧。
- 沿用 `gpu_renderer.zig::isTransientSwapchainError` 的 3 true / 2 false 单测（上一 bug 已加入）。

## Local Verification

- Commands run: `zig build install test` → 0；`zig build install test -Doptimize=ReleaseSafe` → 0；`zig build physics-test` → 0；`zig build test -Ddemo-2d=true` → 0；`zig build test -Dclear-only=true` → 0。恢复正式代码后再次全部重跑，仍为 0。
- Manual check（真实 Wayland 会话，`WAYLAND_DISPLAY=wayland-0`）：由于 SDL 连接真实 GNOME Wayland 合成器而非 Xvfb 显示，XTest 无法稳定注入按键。为确定性验证，临时在 `main.zig` 加入自动切换探针（第 40 帧进入 2D、第 120 帧返回、第 240 帧退出），运行后日志为：
  ```
  [INFO] gpu: 已释放 GPU 窗口绑定（进入 2D 演示）
  [INFO] lobby: 自动进入 2D
  [INFO] gpu: 已重建 GPU surface 与交换链（返回大厅）
  [INFO] lobby: 自动返回大厅
  [INFO] demo: 退出
  ```
  无 `wl_display` 协议错误、无 `Wayland display connection closed`、无 `[ERROR]`，退出码 0。探针已从 `main.zig` 完全移除（`grep AUTO_2D_TEST/auto_frames` 无匹配），最终代码重新构建并通过 G1–G5。
- 反复切换 5 轮与真实键鼠路径未在本次自动探针中覆盖。

## Deviations from Assessment

- 无。实施内容与 Preferred 方案一致；格式变化时按预案返回 `error.SwapchainFormatChanged` 并给出 notice，未继续用错格式渲染。
- 验证手段使用临时自动切换探针（已移除），这是因为当前环境缺少可向真实 Wayland 会话注入键鼠的工具；该手段只用于取证，未留在代码或提交中。

## Follow-ups

- 在有输入设备的真实 Wayland 桌面按 V7 完成 5 轮 demo_2d↔大厅 与 viewer↔大厅 复核，确认无协议错误与 fatal。
- 关注 `releaseWindow`/`claimWindow` 反复调用是否引入资源累积；必要时用 Tracy 观察模式切换开销。
- 多个 bug 目录（lobby-mode-switch-crash / gpu-surface-reclaim-needed）的修复与报告尚未统一提交；确认后按中文 `fix:` 前缀整理为原子提交。
