# Quickstart: 游戏大厅界面验证指南

本指南用于在实现完成后按端到端场景验证大厅功能，不包含实现代码。任务拆解见后续 `/speckit.tasks`，判定规则见 [contracts/acceptance-gates.md](contracts/acceptance-gates.md)，实体与校验规则见 [data-model.md](data-model.md)，设计决策见 [research.md](research.md)。UI 设计验收点 D-01–D-18 见 [ui-design.md](ui-design.md) 第 5 节，作为下列 V1–V6 场景的细化检查项（尤其 D-03/D-04 布局缩放、D-06 防抖、D-08 设置边界、D-11 Esc 矩阵）。

## 前置条件

- Zig **0.17.1**（`zig version` 必须精确匹配；`build.zig` 以 `@compileError` 校验）。
- Linux 桌面或虚拟显示 + Mesa Lavapipe；无桌面时可用 `SDL_VIDEODRIVER=offscreen` 做清屏模式冒烟，或 `SDL_VIDEODRIVER=dummy SDL_RENDER_DRIVER=software` 做 2D 模式冒烟（README「无桌面冒烟测试」）。
- 首次构建允许联网；之后须可离线构建。
- 不修改 `zig-pkg/`、`zig-out/`、`.zig-cache/`。

## 构建与门禁

```sh
zig version                                # 0.17.1
zig build                                  # Debug 安装到 zig-out/bin/
zig build install test                     # 核心/SDL/场景/资产/物理单元测试
zig build install test -Doptimize=ReleaseSafe
zig build physics-test                     # Jolt 无窗口物理测试
zig build test -Ddemo-2d=true              # 2D 模式独立测试
zig build test -Dclear-only=true           # 清屏模式独立测试
```

以上全部退出码 0 为通过（FR-007、FR-011、SC-005）。

## 端到端验证场景

### V1 启动进入大厅（US1 / FR-001 / FR-002 / SC-001）

```sh
zig build run
```

预期：先显示中文大厅而非 3D 场景；大厅可交互；「开始训练」入口可见。点击后进入默认内嵌训练场，HUD、调试面板与操作提示与现有默认模式一致；从启动到可操作不超过两次明确选择、耗时低于 3 秒。启动日志仍应出现 `缓存命中 embedded:demo.glb`。

### V2 Esc 与退出约定（FR-008 / Edge Cases）

1. 在大厅按 Esc：程序不退出、不启动模式，仍停留大厅。
2. 在训练场/外部模型查看/2D/清屏任一模式按 Esc：返回大厅，不退出程序，无卡死或重复窗口。
3. 点击大厅「退出」按钮或关闭窗口：程序干净退出，无残留窗口与资源占用。

### V3 四个模式与二次进入（US2 / FR-003 / FR-005 / SC-002）

预期：大厅列出四个中文模式名称，与 README 叫法一致；逐个选择均能进入对应模式并呈现特有画面；返回大厅后再次进入同一模式，不出现状态残留（角色、靶板、机器人、已加载模型）或资源累积。

### V4 外部模型预览（FR-004 / SC-004）

在大厅选择「外部模型预览」→ 在专门预览界面用文本输入填写/粘贴有效本地 GLB/glTF 路径并确认 → 进入自由飞行查看。

负向路径：路径不存在、格式不支持、依赖的 `.bin`/纹理缺失时，预览界面显示可读错误并允许返回大厅，程序不退出；大厅本身不提供模型路径输入。

### V5 会话设置（US3 / FR-006 / FR-007 / SC-006）

1. 在大厅调整视角灵敏度与音量，界面实时显示当前数值；进入含音效的场景后可观察到相应变化。
2. 输入空值、非数字或越界值（灵敏度 < 0.5 或 > 2.0；音量 < 0 或 > 100）：给出可读提示并收敛到允许范围边界（默认 `1.0` / `100`），不将非法值带入场景。
3. 关闭并重新启动程序：两项设置恢复默认值（不持久化）。
4. 无音频输出设备时：音量仍可调整，进入场景仅记录提示，大厅与场景保持可用。

### V6 窗口缩放与失败处理（FR-010 / FR-012 / Edge Cases）

1. 大厅窗口缩放或最小化再恢复：控件重新排布、仍可点击，不重叠、不隐藏。
2. 任一模式初始化失败（图形设备不可用、音频设备缺失、模型加载失败）：显示可读错误并停留大厅，可重试或改选，程序不退出。
3. 连续快速点击多个模式入口：只进入最后确认的一个模式，不出现多次初始化或窗口冲突。

### V7 返回大厅稳定性回归（bug: gpu-surface-reclaim-needed）

针对广告 `wp_fifo_manager_v1` 的 Wayland 合成器（Xvfb/X11 基线无法复现，需在真实 Wayland 桌面或 `WAYLAND_DISPLAY` 可用的环境执行）：

```sh
zig build run
```

1. 在 lobby 选中「2D 输入演示」并确认，进入 demo_2d；按 Esc 返回大厅，反复 5 轮。
2. 在 lobby 选中「外部模型预览」→ 填有效 GLB → 加载进入 viewer；按 Esc 返回大厅，反复 5 轮。
3. 断言：进程始终存活；日志无 `wp_fifo_manager_v1 … get_fifo` 协议错误、无 `Wayland display connection closed by server (fatal)`、无 `[ERROR] gpu: 获取交换链图像失败`；进入 2D 时应出现 `已释放 GPU 窗口绑定`，离开时应依次出现 `已释放 2D 渲染器`、`已重建 GPU surface 与交换链`，随后有新的 `已提交 … 帧`。
4. 断言：`缓存命中 embedded:demo.glb` 仍在首次启动时出现；再次进入训练场的角色、靶板与机器人状态为初始状态。

## 完成判定

- SC-001：启动到开始操作训练场 ≤2 次选择且 <3 秒。
- SC-002：四个模式均能一次选择进入并呈现特有画面。
- SC-003：README「手动验收」清单对应条目保持通过，命中判定、武器参数、机器人行为和结算重开不变。
- SC-004：四类异常场景 100% 给出可读反馈且程序可继续操作。
- SC-005：上述构建/测试门禁全通过，不新增外部依赖。
- SC-006：设置调整后无需重启即可在场景中观察到变化。
