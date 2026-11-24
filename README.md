# Zig SDL3 Demo

这个 2D Demo 用于验证框架 M0 的构建与核心模块，以及 M1 的窗口、事件和输入链路。

使用 Zig **0.17.1**。编辑器建议使用配套的 ZLS **0.17.0**，构建和运行不依赖 ZLS。SDL 绑定提交及内容哈希锁定在 [build.zig.zon](build.zig.zon)，绑定会从源码构建 SDL **3.4.20**。第一次构建需要下载依赖。交互验收使用具有可用 SDL 视频后端的 Linux 桌面。

```sh
zig version
zig build
zig build -Doptimize=ReleaseSafe
zig build test
zig build run
```

M1 交互验收：

1. 调整窗口大小、最小化并恢复。确认终端显示逻辑尺寸和像素尺寸，矩形随可绘制区域调整位置。
2. 按住 WASD，确认矩形随方向偏移。快速点击左键，确认终端记录按下，矩形变色。
3. 按 Tab 切换相对鼠标模式。捕获后移动鼠标，确认矩形随增量移动。切换到其他窗口时应清除按住的动作并释放捕获，回到窗口后可用 Tab 再次捕获。
4. 分别使用 Esc 和窗口关闭按钮退出。

无桌面环境可用 SDL `dummy` 视频驱动和软件渲染器检查启动、绘制循环和 SIGTERM 退出：

```sh
zig build
timeout --preserve-status 3s env SDL_VIDEODRIVER=dummy SDL_RENDER_DRIVER=software ./zig-out/bin/zigsdl3demo
```

此检查不覆盖桌面窗口管理器、焦点切换或真实鼠标捕获。SDL GPU 和着色器属于后续里程碑。
