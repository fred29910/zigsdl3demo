# Zig SDL3 Demo

默认 Demo 在 SDL GPU / Vulkan 上通过 Render Queue 绘制两个父子立方体和后方的索引三角形，带自由飞行相机和 Dear ImGui 帧时间面板。M1 的 2D 输入演示和 M2 的清屏模式仍可单独运行。

使用 Zig **0.17.1**。编辑器建议使用配套的 ZLS **0.17.0**，构建和运行不依赖 ZLS。SDL 绑定提交及内容哈希锁定在 [build.zig.zon](build.zig.zon)，绑定会从源码构建 SDL **3.4.20**。第一次构建需要下载依赖。交互验收使用具有可用 SDL 视频后端的 Linux 桌面。

```sh
zig version
zig build
zig build -Doptimize=ReleaseSafe
zig build test
zig build run
```

### M4 场景验收

在带 Vulkan loader 和可用驱动的 Linux 桌面进行以下检查。

1. 运行 `zig build run`。大立方体在原地旋转，小立方体随父实体绕行并可被遮挡，三角形在后方。左上角面板显示帧时间、FPS 和 `Opaque draws: 3`。
2. 光标自由时拖动 `Rotation` 滑块，确认两级立方体的运动同时变速。按 Tab 捕获鼠标后，可以移动鼠标观察场景，WASD 飞行，空格上升、左 Ctrl 下降、左 Shift 加速。再按 Tab 释放。
3. 调整窗口大小并确认模型比例和面板位置正常。最小化后恢复应继续绘制。按 Esc 或点关闭按钮退出。

Registry 用索引和代数标识实体。父实体销毁或移除 Transform 时，直接子实体保留其局部变换并成为根实体。Render Queue 收集同时带 Transform 和 MeshRenderer 的实体，按材质、网格和实体索引排序。当前网格和材质是内置资源。GLB/GLTF 导入和资源缓存属于 M5。

`zig build test` 覆盖旧实体句柄、父子变换与循环检测、组件移除、绘制筛选及队列排序。

构建会从内容哈希锁定的 [Dear ImGui v1.92.5](https://github.com/ocornut/imgui/tree/v1.92.5) 源码编译官方 SDL3 / SDL GPU 后端，两者与 Demo 共用一份 SDL。项目使用小型 C ABI 桥接 ImGui。

### 从 HLSL 构建着色器

着色器源文件在 [shaders](shaders)。如果 PATH 中存在 `shadercross`，默认构建会离线生成并嵌入 SPIR-V。也可显式指定启用了 DXC 的 SDL_shadercross CLI：

```sh
zig build -Dshadercross=/path/to/shadercross
zig build shaders -Dshadercross=/path/to/shadercross
cmp shaders/demo.vert.spv zig-out/shaders/demo.vert.spv
cmp shaders/demo.frag.spv zig-out/shaders/demo.frag.spv
```

未安装编译器时，普通构建嵌入仓库中的 SPIR-V。修改 HLSL 后需运行 `zig build shaders`，并用生成产物更新仓库中的对应文件。当前产物已用 [SDL_shadercross 1ff05be](https://github.com/libsdl-org/SDL_shadercross/tree/1ff05bec573988a98ef9e0260b4da44f512b8367) 和 [DXC v1.8.2505.1](https://github.com/microsoft/DirectXShaderCompiler/releases/tag/v1.8.2505.1) 重新生成并逐字节核对。运行时不依赖 shadercross 或外部 shader 文件。

### M2 清屏验收

1. 运行 `zig build run -Dclear-only=true`。预期窗口显示深蓝色，日志报告 `vulkan` 后端、SPIR-V 支持、交换链格式和首帧尺寸。
2. 调整尺寸、最小化再恢复。恢复后应继续清屏，尺寸改变时日志应显示新交换链尺寸。
3. 分别使用 Esc 和窗口关闭按钮退出。Demo 会等待 GPU 空闲，释放交换链和设备后再销毁窗口。

M2 使用 SDR 和 VSync。清屏由 Render Pass 的 clear 操作完成，无需着色器文件。

无桌面环境下，可用支持 Vulkan headless surface 的 SDL `offscreen` 后端验证交换链清屏和 SIGTERM 退出。以下以安装 Mesa Lavapipe 的 Linux 环境为例，按本机调整 ICD 路径：

```sh
zig build
timeout --preserve-status --kill-after=2s 3s env \
  SDL_VIDEODRIVER=offscreen VK_DRIVER_FILES=/usr/share/vulkan/icd.d/lvp_icd.json \
  ./zig-out/bin/zigsdl3demo
```

### M1 输入验收

运行 `zig build run -Ddemo-2d=true`：

1. 调整窗口大小、最小化并恢复。确认终端显示逻辑尺寸和像素尺寸，矩形随可绘制区域调整位置。
2. 按住 WASD，确认矩形随方向偏移。快速点击左键，确认终端记录按下，矩形变色。
3. 按 Tab 切换相对鼠标模式。捕获后移动鼠标，确认矩形随增量移动。切换到其他窗口时应清除按住的动作并释放捕获，回到窗口后可用 Tab 再次捕获。
4. 分别使用 Esc 和窗口关闭按钮退出。

无桌面环境仍可用 SDL `dummy` 视频驱动检查 M1 的 2D 路径。该驱动不支持 M2 的 Vulkan 窗口：

```sh
zig build -Ddemo-2d=true
timeout --preserve-status 3s env SDL_VIDEODRIVER=dummy SDL_RENDER_DRIVER=software ./zig-out/bin/zigsdl3demo
```

### 验证记录

M4 的 Debug、ReleaseSafe 和 `zig build test` 通过。在 Xvfb + Lavapipe 上读取窗口像素，确认子立方体绕行时可与主体分开，窗口从 800×600 缩放至 640×480 后仍能绘制。M1 的 2D 模式和 M2 的清屏模式也通过了启动与退出验证。

M3 的 Debug、ReleaseSafe、`zig build test` 通过。在 Xvfb + Lavapipe 上读取实际窗口像素，确认棋盘纹理、旋转、ImGui 文本、800×600 → 640×480 resize 和 Tab 捕获后按 W 的相机移动。SDL offscreen 启动绘制并响应 SIGTERM 正常退出。真实桌面窗口管理器的最小化、恢复及硬件 Vulkan 驱动仍待验收。

M2 在同一虚拟显示配置下，resize 前后窗口中心像素均为 RGB (26, 51, 102)，交换链提交尺寸随窗口更新。
