# Bug Fix: 返回大厅后交换链 surface 丢失（补修未奏效）

- **Slug**: lobby-mode-switch-crash
- **Fixed**: 2026-11-26
- **Assessment**: ./assessment.md
- **Status**: partial

## Summary

按重新评估后的 Preferred 方案，在离开 demo_2d 模式时释放软件 `renderer_2d`，并在 V7 中加入该路径；连同上一轮已落地的 `reloadModel` 与瞬时错误跳帧，G1–G5 全部通过。但同一 Wayland 复现脚本显示：清理确实执行（`已释放 2D 渲染器`），协议错误、`VK_ERROR_SURFACE_LOST_KHR`、合成器关闭连接与进程退出**仍然发生**。因此本轮修复未奏效，按命令约束停止继续改代码并记录偏差。

## Changes

| File | Change | Notes |
|------|--------|-------|
| `src/main.zig` | modified | Esc 离开 demo_2d 时释放鼠标捕获、调用 `renderer_2d.deinit()` 并置 null，新增 `已释放 2D 渲染器` 日志 |
| `src/engine/renderer/demo_scene.zig` | modified（上一轮） | 事务式 `reloadModel`，模式切换不再重建 ImGui/GPU 后端 |
| `src/engine/renderer/gpu_renderer.zig` | modified（上一轮） | `isTransientSwapchainError` 单测 + 瞬时错误 WARN 跳帧 |
| `specs/001-game-lobby-ui/quickstart.md` | modified | V7 增加 demo_2d → 大厅 5 轮回归断言 |

## Diff Highlights (optional)

```zig
// main.zig — 本轮新增（已证实不足）
} else if (session.view == .demo_2d) {
    if (input.mouseCaptured()) setCapture(&input, false);
    if (renderer_2d) |r| {
        r.deinit();
        renderer_2d = null;
        log.log(.info, "lobby", "已释放 2D 渲染器", .{});
    }
    lobby.returnToLobby(&session);
}
```

## Tests Added or Updated

- `specs/001-game-lobby-ui/quickstart.md::V7` — 真实 Wayland 下 demo_2d→大厅 与 viewer→大厅 各 5 轮，断言无协议错误、无 fatal、进程存活。
- `src/engine/renderer/gpu_renderer.zig::isTransientSwapchainError` — 3 true / 2 false，保留。

## Local Verification

- Commands run: `zig build install test` → 0；`zig build install test -Doptimize=ReleaseSafe` → 0；`zig build physics-test` → 0；`zig build test -Ddemo-2d=true` → 0；`zig build test -Dclear-only=true` → 0。
- Manual check: Xvfb + XTest，`WAYLAND_DISPLAY=wayland-0`，复现序列 `Escape, Return, Escape, Escape, Tab+Return, Escape`，模式日志 `进入模式: demo_2d`。
- 关键日志（`/tmp/opencode/fix2-smoke.log`）：
  ```
  [INFO] lobby: 已释放 2D 渲染器
  [INFO] lobby: 返回大厅
  wl_display#1: error 1: invalid arguments for wp_fifo_manager_v1#70.get_fifo
  [WARN] gpu: 交换链暂时不可用，跳过本帧: vkGetPhysicalDeviceSurfaceFormatsKHR VK_ERROR_SURFACE_LOST_KHR   （连续 12 次）
  ERROR: Wayland display connection closed by server (fatal)
  [INFO] demo: 退出
  ```
- 结论：清理逻辑确实执行，但 bug 未消除；进程在返回大厅后退出。`缓存命中 embedded:demo.glb` 仍出现。

## Deviations from Assessment

- 重评估的 Preferred 方案是「离开 demo_2d 时销毁 `renderer_2d`」。已按字面实施并验证：日志确认销毁发生，但协议错误与 fatal 紧随其后，方案无效。
- 这说明重评估的根因假设仍不完整：问题不只是「退出时软件渲染器未销毁」。可能是在 GPU 已 `claimWindow` 的窗口上创建软件渲染器时，Wayland surface/fifo 状态就已被污染；或 `renderer_2d.deinit()` 自身触发 surface 失效。需要重新评估才能确定。
- 对照证据：大厅 Esc、训练场 Esc→大厅均无此错误；仅 demo_2d 往返复现。上一轮的 `reloadModel` 与瞬时错误跳帧都不触及该路径（跳帧只把 `[ERROR]` 降为 `[WARN]`，无法阻止合成器关闭连接）。
- 按 `/speckit.bug.fix` 约束，发现方案无效后停止继续修改代码，未尝试额外规避手段（如 XWayland 或独立窗口）。

## Follow-ups

- 重新运行 `/speckit.bug.assess slug=lobby-mode-switch-crash`，纳入「销毁 renderer_2d 后仍复现」的证据。
- 待评估的候选方向：默认构建不再在同一窗口上使用软件渲染器（改用 GPU 绘制 2D，或为 2D 演示使用独立窗口）；或记录 `SDL_VIDEO_DRIVER=x11` 走 XWayland 的环境级规避。
- V7 已作为可复现的失败回归保留；在真实 Wayland 桌面确认通过前，不得声称该 bug 已修复。
- 改动尚未提交（工作区包含本轮 main.zig 与 quickstart.md 修改，以及上一轮被外部自动提交 `eeaac61` 包含的加固改动）。
