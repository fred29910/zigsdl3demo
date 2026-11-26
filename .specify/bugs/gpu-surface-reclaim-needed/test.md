# Bug Verification: 2D 模式切回 GPU 后 surface 重建

- **Slug**: gpu-surface-reclaim-needed
- **Tested**: 2026-11-26
- **Assessment**: ./assessment.md
- **Fix**: ./fix.md
- **Result**: partial

## Summary

修复后的构建与全部测试门禁通过；但本轮**未能重新执行原始键鼠复现路径**——XTest/XSendEvent 键盘事件无法送入 SDL 窗口（鼠标点击可以送达），因此无法在本次运行中确认原症状已消失。上一轮 fix 阶段的临时自动切换探针曾在真实 Wayland 上观察到释放/重建全程无协议错误，但该探针已移除，按本命令约束不能再次临时改源码复跑。据此降级为 partial，不作 verified 结论。

## Checks Performed

| Check | Command / Action | Result | Notes |
|-------|------------------|--------|-------|
| Reproduction (post-fix) | `zig build run` + Xvfb/XTest（`Escape`/`Return`/`Tab`）与 `SDL_VIDEO_DRIVER=x11` 变体 | not-run | 按键注入未送达 SDL：日志无 `进入模式`，仅鼠标点击产生 `input: 检测到左键按下`。无法触发 demo_2d→大厅 路径 |
| Reproduction (prior evidence) | fix 阶段临时自动切换探针（已移除） | inconclusive | 曾记录 `已释放 GPU 窗口绑定` → `已重建 GPU surface 与交换链` → 正常退出，无 `wl_display`/fatal；本轮未复跑 |
| New / updated tests | `zig build install test`（含 `isTransientSwapchainError` 单测） | pass | 退出码 0 |
| Regression suite | `zig build install test -Doptimize=ReleaseSafe`、`zig build physics-test`、`zig build test -Ddemo-2d=true`、`zig build test -Dclear-only=true` | pass | 全部退出码 0 |
| Lint / type-check | `zig build`（Zig 0.17.1 编译即类型检查） | pass | 退出码 0；`build.zig:53` 守护仍在 |

## Output Excerpts

```
G1_PASS / G2_PASS / G3_PASS / G4_PASS / G5_PASS
test-g1.log: 0 处 fail/error
```

复现尝试（`/tmp/opencode/test-repro.log`）：

```
[INFO] demo: 大厅选择模式进入；...
[INFO] window: 窗口 2880x1544，像素 2880x1544
（无 进入模式 / 无 返回大厅 / 无 已释放 GPU 窗口绑定）
```

fix 阶段探针证据（`/tmp/opencode/fix3-auto.log`，非本轮复跑）：

```
[INFO] gpu: 已释放 GPU 窗口绑定（进入 2D 演示）
[INFO] gpu: 已重建 GPU surface 与交换链（返回大厅）
[INFO] demo: 退出
```

## Residual Risks

- 本轮未实际驱动 demo_2d→Esc→大厅，无法排除修复在真实键鼠路径上仍有协议错误。
- 自动探针只覆盖一次往返；V7 要求的 5 轮切换与资源累积未验证。
- 当前环境缺少可向 SDL 窗口可靠注入键盘的工具（无 xdotool/ydotool，/dev/uinput 权限不足，XSendEvent 被 SDL 忽略）。
- 交换链格式变化分支（`error.SwapchainFormatChanged`）未被触发验证。

## Recommendation

Hold——不要把该 bug 标记为已关闭。构建与单测证据充分，但原始复现路径在本轮未实际执行，按约束只能判 partial。请在有键盘输入能力的真实 Wayland 桌面按 `quickstart.md` V7 完成 5 轮切换复核；若通过，再将结果更新为 verified 并关闭 bug。
