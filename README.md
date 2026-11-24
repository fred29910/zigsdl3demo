# Zig SDL3 Demo

默认 Demo 从内嵌的 `assets/demo.glb` 加载两个父子立方体、后方的三角形和地面，经 Render Queue 在 SDL GPU / Vulkan 上绘制。立方体使用法线贴图，方向光在地面投下阴影。可用自由飞行相机查看场景和天空盒，Dear ImGui 面板显示帧时间和绘制次数。M1 的 2D 输入演示和 M2 的清屏模式仍可单独运行。

使用 Zig **0.17.1**。编辑器建议使用配套的 ZLS **0.17.0**，构建和运行不依赖 ZLS。SDL 绑定提交及内容哈希锁定在 [build.zig.zon](build.zig.zon)，绑定会从源码构建 SDL **3.4.20**。第一次构建需要下载依赖。交互验收使用具有可用 SDL 视频后端的 Linux 桌面。

```sh
zig version
zig build
zig build -Doptimize=ReleaseSafe
zig build test
zig build run
```

### M6 光照验收

1. 运行 `zig build run`。观察立方体随旋转改变的明暗和高光。同色棋盘格内可见由法线贴图产生的明暗起伏。
2. 观察立方体和三角形在地面投下的阴影，旋转中的立方体会带动阴影移动。
3. 按 Tab 捕获鼠标。平移时远处天空保持固定，转动视角时天空随视角变化。

渲染先用 2048×2048 深度纹理绘制方向光阴影，再绘制 Blinn–Phong 场景、天空盒和 ImGui。阴影范围按场景实例包围盒计算，采样使用 3×3 PCF。透明裁剪材质在主渲染和投影时使用同一 Base Color alpha 阈值。天空盒使用程序生成的六面立方体贴图。

法线贴图使用线性采样数据和 glTF 的 `normalTexture.scale`。顶点缺少切线时从位置和 UV 的屏幕导数重建切线，缺少法线时使用几何法线。Blinn–Phong 使用材质的 Roughness 系数控制高光，`KHR_materials_unlit` 材质沿用 Base Color。Metallic 和 Metallic/Roughness 贴图保留给 PBR。

### M5 资产验收

```sh
zig build test
zig build run
zig build run -- assets/demo.glb
zig build run -- /path/to/scene.gltf
```

在带 Vulkan loader 和可用驱动的 Linux 桌面进行以下检查。

1. 运行 `zig build run`。大立方体在原地旋转，小立方体随父实体绕行，三角形位于后方。两组立方体共享网格，面板显示 `Opaque draws: 6`，其中包含 M6 新增的地面。
2. 检查日志中的 `已加载 embedded:demo.glb` 和 `缓存命中 embedded:demo.glb，引用数 2`。Demo 会请求同一资源两次，第二次复用已上传的资源。
3. 用命令行传入本地 GLB 或 glTF。外部模型保持文件中的节点变换，文件路径和加载失败原因会写入日志。
4. 默认场景可拖动 `Rotation` 滑块调节转速。按 Tab 捕获或释放鼠标，捕获后用鼠标观察，WASD 飞行，空格上升、左 Ctrl 下降、左 Shift 加速。按 Esc 或点关闭按钮退出。

支持 glTF 2.0 静态三角形场景、多网格和多 primitive、索引和非索引几何、矩阵及 TRS 节点、UV0、法线和文件提供的切线。PNG/JPEG 纹理可来自 GLB buffer view、相对路径或 base64 data URI。支持 Base Color 纹理和系数、不透明和透明裁剪材质。

当前使用纹理基础层。动画、蒙皮、Morph、压缩网格、混合透明、纹理变换和其他 UV 通道超出 M5 导入范围。相机沿用 Demo 的初始位置与裁剪范围，查看外部模型时可手动移动。

AssetManager 以规范绝对路径缓存文件，以名称缓存内嵌资源。调用方在场景实体存活期间持有 ModelHandle。最终释放时会使该模型及其网格、纹理、材质句柄失效，由 SDL GPU 在安全时销毁其 GPU 对象。

`zig build test` 覆盖实体句柄、父子变换与循环检测、队列排序、GLB 数据导入、base64 缓冲区和越界数据检查。

构建使用带内容哈希的 cgltf v1.15 和 stb_image v2.30。C 声明通过 Zig 构建系统的 TranslateC 生成。 [cgltf v1.15](https://github.com/jkuhlmann/cgltf/releases/tag/v1.15) [stb 固定提交](https://github.com/nothings/stb/tree/f0569113c93ad095470c54bf34a17b36646bbbb5)

构建会从内容哈希锁定的 [Dear ImGui v1.92.5](https://github.com/ocornut/imgui/tree/v1.92.5) 源码编译官方 SDL3 / SDL GPU 后端，两者与 Demo 共用一份 SDL。项目使用小型 C ABI 桥接 ImGui。

### 从 HLSL 构建着色器

着色器源文件在 [shaders](shaders)。如果 PATH 中存在 `shadercross`，默认构建会离线生成并嵌入 SPIR-V。也可显式指定启用了 DXC 的 SDL_shadercross CLI：

```sh
zig build -Dshadercross=/path/to/shadercross
zig build shaders -Dshadercross=/path/to/shadercross
for shader in shaders/*.spv; do
  cmp "$shader" "zig-out/$shader" || exit 1
done
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

M6 的 Debug、ReleaseSafe、`zig build test` 及 M1/M2 两个独立模式的构建测试通过。在 Xvfb + Lavapipe 上读取窗口像素，确认阴影随立方体移动、透明裁剪形状影响投影、法线贴图生效、天空随转向变化，以及 800×600 → 640×480 后继续绘制。法线贴图对照使用了带切线、缺少切线和移除法线贴图的三组外部 GLB。

M5 的 Debug、ReleaseSafe 和 `zig build test` 通过。Xvfb + Lavapipe 像素测试确认内嵌 GLB 的棋盘纹理、父子绕行和 800×600 → 640×480 缩放。软件 Vulkan 还验证了外部 GLB、相对路径 PNG/JPEG 和 base64 data URI 场景。重复请求记录一次加载和一次缓存命中，缺失外部缓冲区时返回 `FileNotFound`。

M4 的 Debug、ReleaseSafe 和 `zig build test` 通过。在 Xvfb + Lavapipe 上读取窗口像素，确认子立方体绕行时可与主体分开，窗口从 800×600 缩放至 640×480 后仍能绘制。M1 的 2D 模式和 M2 的清屏模式也通过了启动与退出验证。

M3 的 Debug、ReleaseSafe、`zig build test` 通过。在 Xvfb + Lavapipe 上读取实际窗口像素，确认棋盘纹理、旋转、ImGui 文本、800×600 → 640×480 resize 和 Tab 捕获后按 W 的相机移动。SDL offscreen 启动绘制并响应 SIGTERM 正常退出。真实桌面窗口管理器的最小化、恢复及硬件 Vulkan 驱动仍待验收。

M2 在同一虚拟显示配置下，resize 前后窗口中心像素均为 RGB (26, 51, 102)，交换链提交尺寸随窗口更新。
