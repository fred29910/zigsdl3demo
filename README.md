# Zig SDL3 Demo

默认 Demo 使用 SDL GPU 在 Vulkan 上做固定色清屏，用于验证 M2。M1 的 2D 输入演示可用 `-Ddemo-2d=true` 运行。

使用 Zig **0.17.1**。编辑器建议使用配套的 ZLS **0.17.0**，构建和运行不依赖 ZLS。SDL 绑定提交及内容哈希锁定在 [build.zig.zon](build.zig.zon)，绑定会从源码构建 SDL **3.4.20**。第一次构建需要下载依赖。交互验收使用具有可用 SDL 视频后端的 Linux 桌面。

```sh
zig version
zig build
zig build -Doptimize=ReleaseSafe
zig build test
zig build run
```

M2 交互验收使用带 Vulkan loader 和可用驱动的 Linux 桌面：

1. 运行 `zig build run`。预期窗口显示深蓝色，日志报告 `vulkan` 后端、SPIR-V 支持、交换链格式和首帧尺寸。
2. 调整尺寸、最小化再恢复。恢复后应继续清屏，尺寸改变时日志应显示新交换链尺寸。
3. 分别使用 Esc 和窗口关闭按钮退出。Demo 会等待 GPU 空闲，释放交换链和设备后再销毁窗口。

M2 使用 SDR 和 VSync。清屏由 Render Pass 的 clear 操作完成，无需着色器文件。Shader 和绘制管线属于 M3。

无桌面环境下，可用支持 Vulkan headless surface 的 SDL `offscreen` 后端验证交换链清屏和 SIGTERM 退出。以下以安装 Mesa Lavapipe 的 Linux 环境为例，按本机调整 ICD 路径：

```sh
zig build
timeout --preserve-status --kill-after=2s 3s env \
  SDL_VIDEODRIVER=offscreen VK_DRIVER_FILES=/usr/share/vulkan/icd.d/lvp_icd.json \
  ./zig-out/bin/zigsdl3demo
```

M1 交互验收使用 `zig build run -Ddemo-2d=true`：

1. 调整窗口大小、最小化并恢复。确认终端显示逻辑尺寸和像素尺寸，矩形随可绘制区域调整位置。
2. 按住 WASD，确认矩形随方向偏移。快速点击左键，确认终端记录按下，矩形变色。
3. 按 Tab 切换相对鼠标模式。捕获后移动鼠标，确认矩形随增量移动。切换到其他窗口时应清除按住的动作并释放捕获，回到窗口后可用 Tab 再次捕获。
4. 分别使用 Esc 和窗口关闭按钮退出。

无桌面环境仍可用 SDL `dummy` 视频驱动检查 M1 的 2D 路径。该驱动不支持 M2 的 Vulkan 窗口：

```sh
zig build -Ddemo-2d=true
timeout --preserve-status 3s env SDL_VIDEODRIVER=dummy SDL_RENDER_DRIVER=software ./zig-out/bin/zigsdl3demo
```

M2 验证记录：Debug、ReleaseSafe 和 `zig build test` 通过。在 Xvfb + Lavapipe 上读取窗口中心像素，窗口从 800×600 调至 640×480 前后均为 RGB (26, 51, 102)，交换链提交尺寸随窗口更新，收到 SIGTERM 后正常退出。虚拟显示器未覆盖桌面窗口管理器的最小化或实际鼠标捕获。
