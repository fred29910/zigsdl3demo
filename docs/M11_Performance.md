# M11 性能与发布验收

## 采样环境

- Linux x86-64，Intel Core i9-13900H，Zig 0.17.1，ReleaseSafe。
- Xvfb 窗口 800×600，Mesa Lavapipe 软件 Vulkan，交换链启用 VSync，阴影图分辨率 2048×2048。音频送到隔离的 ALSA null 设备。
- Tracy v0.12.2 从同机采样 14.08 秒，共记录 907 个帧标记和 7,178 个 CPU 分区事件。采样覆盖开火、换弹、巡逻与追击、玩家受伤、失败结算和原窗口重开。

## 结果

| Tracy 分区 | 样本数 | 平均耗时（ms） | P95（ms） | 最大（ms） |
| --- | ---: | ---: | ---: | ---: |
| Scene frame | 903 | 15.4593 | 18.0059 | 32.5857 |
| Submit frame | 903 | 15.1559 | 17.5163 | 31.7814 |
| Acquire swapchain | 904 | 0.0534 | 0.0871 | 0.2552 |
| Record render passes | 904 | 0.1788 | 0.2767 | 0.5551 |
| Render queue | 904 | 0.0126 | 0.0204 | 0.0481 |
| Training update | 904 | 0.0545 | 0.1069 | 1.3467 |
| Jolt simulation | 877 | 0.0509 | 0.1016 | 1.3393 |
| Robot and round | 877 | 0.0037 | 0.0062 | 0.0343 |

表中统计完整的 CPU 分区事件。跟踪边界、暂停及结算会造成各分区计数与帧标记数不同。分区存在嵌套关系，`Scene frame` 含渲染和训练更新，`Training update` 含 Jolt 和机器人更新。

`Submit frame` 占 `Scene frame` 平均耗时约 98%，主要耗时集中在 SDL GPU 提交和呈现调用。这个调用包含驱动与呈现等待，样本没有 Vulkan GPU 时间戳，无法继续划分绘制、驱动和 VSync 的耗时。当前场地的机器人与物理更新 P95 分别约为 0.006 ms 和 0.102 ms。以上数字适用于该软件 Vulkan 场景，实体 GPU 上的表现仍需实测。

## 复现采样

使用 [Tracy v0.12.2](https://github.com/wolfpld/tracy/tree/v0.12.2) 的同版本客户端和采集器。将以下命令里的源码目录替换成本地路径。

```sh
zig build install -Doptimize=ReleaseSafe \
  -Dtracy-source=/path/to/tracy-0.12.2 --prefix zig-out/profile
cmake -S /path/to/tracy-0.12.2/capture -B /tmp/tracy-capture \
  -DCMAKE_BUILD_TYPE=Release -DNO_FILESELECTOR=ON
cmake --build /tmp/tracy-capture
./zig-out/profile/bin/zigsdl3demo
```

在另一个终端执行以下命令。回到游戏按 Tab，完成开火、换弹、靠近机器人、被击倒和按 E 重开的流程。

```sh
/tmp/tracy-capture/tracy-capture -a 127.0.0.1 -s 14 -o range.tracy
```

用 Tracy 查看 `range.tracy`，或从同一源码的 `csvexport` 目录构建 `tracy-csvexport`。聚合结果使用默认输出，P95 使用 `-u` 的逐事件耗时，按分区对 `exec_time_ns` 排序并取第 `ceil(0.95 × N)` 项。普通发布构建省略 `-Dtracy-source`。

## 发布验证

- Debug、ReleaseSafe、SDL 2D 和 Vulkan 清屏配置通过构建和测试。外部 GLB 查看模式通过启动、提交帧和退出检查。
- Xvfb/Lavapipe 下使用 ReleaseSafe 实际操作。机器人进入追击和攻击，暂停时玩家生命保持，恢复后验证失败和胜利。三次重开均恢复 40 个实体、10 个刚体、100 HP 和 6 发弹药，场地模型和音频各初始化一次。
- 独立物理测试覆盖路点最短路线、遮挡中断攻击蓄力和运动学实体同步。Blender 5.2.0 后台重新导出场地 GLB，与仓库产物逐字节一致。
- Linux x86-64 可执行文件使用 `zig build -Doptimize=ReleaseSafe` 生成。内嵌场地、模型和 SPIR-V，从任意工作目录可启动。
