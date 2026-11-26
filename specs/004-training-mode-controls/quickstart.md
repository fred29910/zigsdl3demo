# Quickstart: 训练模式操控完善验证

**Feature**: `004-training-mode-controls` | **Date**: 2026-11-26

本指南只描述如何验证本特性是否生效，不包含实现代码。行为细则见 [contracts/input-controls.md](contracts/input-controls.md)，状态规则见 [data-model.md](data-model.md)，验收指标见 [spec.md](spec.md) 的 SC-001–SC-006。

## 前置条件

- Zig 版本精确为 `0.17.1`（`zig version` 校验；构建脚本另有 `@compileError` 检查）。
- 首次构建需联网获取锁定依赖；本地需具备 Vulkan loader 与 SDL 视频后端。软件验收基线为 Mesa Lavapipe。
- 工作目录为仓库根目录，勿改动 `zig-pkg/`、`zig-out/`、`.zig-cache/`。

## 自动化验证（必须全部通过）

```sh
zig version
zig build install test
zig build physics-test
zig build test -Ddemo-2d=true
zig build test -Dclear-only=true
zig build install test -Doptimize=ReleaseSafe
```

预期：`zig build install test` 覆盖输入边沿/鼠标增量与灵敏度映射；`zig build physics-test` 覆盖方向、斜向限速、冲刺、单次起跳与捕获丢失取消；两种基础模式测试独立通过；ReleaseSafe 复测无回归。

## 端到端手动验收（Linux 虚拟显示 + 软件 Vulkan）

```sh
zig build run
```

1. 启动后先进入中文大厅；把视角灵敏度分别设为 0.5 与 2.0，进入训练场并按 Tab 捕获鼠标。施加相同鼠标位移：2.0 档的转向约为 0.5 档的四倍，方向一致（SC-001）。
2. 持续向上/下移动鼠标，视线到达上下限后停住，不绕回、不翻转（SC-002）。
3. 依次按 W/A/S/D，角色沿视线前/左/后/右移动；再按 W+D 斜向移动，位移不超过单方向的 1.05 倍；按 W+S 时静止（SC-003、契约边界）。
4. 按住 Shift+W 移动，速度提升稳定；按住空格不放，角色只起跳一次，松开再按才会再次起跳（SC-004）。
5. 贴住围墙斜向顶墙移动：沿墙滑动、不穿透、不卡死；跳上低障碍后恢复着地（FR-009）。
6. 按住移动键时让窗口失焦或按 Tab 释放鼠标：角色在下一帧停止，鼠标移动不再改变视角（SC-005、FR-004/010）。
7. 使回合结束（击倒目标或生命归零）后按 E 重开：视角回出生朝向、角色回出生点且可移动，之前的按住状态不残留；再进入 2D 与清屏演示，确认互相独立（SC-006、FR-011/012）。

## 无桌面冒烟（可选）

```sh
zig build -Dclear-only=true --prefix zig-out/clear
timeout --preserve-status --kill-after=2s 3s env \
  SDL_VIDEODRIVER=offscreen \
  VK_DRIVER_FILES=/usr/share/vulkan/icd.d/lvp_icd.json \
  ./zig-out/clear/bin/zigsdl3demo
```

清屏模式仍应正常启动、清屏并退出；ICD 路径按本机调整。

## 完成判定

自动化命令全部退出码为 0，手动验收 1–7 与契约逐条一致，且 README 的操作表与「测试与验收」已同步本特性结论，即可判定本特性验证完成。
