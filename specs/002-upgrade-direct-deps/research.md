# Research: 升级直接依赖至最新版本（刷新跑，2026-11-26）

**方法**：`build.zig.zon`（2026-11-26）为当前锁定基线；`websearch` + `librarian` 经 GitHub API/Releases/Web 官方渠道查询上游最新稳定版。调研允许联网；升级完成后必须离线可构建（G6，见 quickstart.md）。

## R1 — 每项直接依赖的当前锁定、上游最新与判定

**当前锁定快照（`build.zig.zon`，2026-11-26）**：

| 依赖 | 名称 | 来源类型 | 当前版本标识 | 当前内容哈希 |
| --- | --- | --- | --- | --- |
| jolt | `jolt` | release tag | v5.7.0 | `N-V-__8AAJgyLAL_wh69ee1vC-XK3z_zAims-XlafozU6HDG` |
| cgltf | `cgltf` | release tag | v1.15 | `N-V-__8AAKFjBABZzn84N4iiLQyNQSMVsv5XBJSvZTPcQL2H` |
| stb | `stb` | 提交 SHA | `6b5799bae8a1fe3792691ef4b72ae26434c3e799` | `N-V-__AAMNjVQBtQqFTqLXf4ajZ6COgMe1AG_STJHG4jkdj` |
| imgui | `imgui` | release tag | v1.93.0 | `N-V-__8AAEVjfgCU7hthaWtlDkNjFB4HE1XYqFl6UO7oqXwD` |
| miniaudio | `miniaudio` | release tag | 0.11.26 | `N-V-__8AAOYywgDjFH2rxtvPz3D1RS7WRGMqfpncZjJW-jIl` |
| sdl3 | `sdl3` | git 固定提交 | `aaa5868464855ab0bda4dffe1cf424709f665669` | `sdl3-0.1.0-WOwCypO_BACuJ0ijR3Y3kamzX0Ds_uzIaY-ucLwBdPog` |

**上游最新（调研结果，2026-11-26）**：

| 依赖 | 上游最新 | 是否比锁定新 | 来源/理由 |
| --- | --- | --- | --- |
| Jolt Physics | v5.7.0（2026-11-14） | 否 | jrouwe/JoltPhysics 官方 Release 列表；v5.6.0 为 2026-07-11，v5.7.0 早于 2026-11-26；锁定为稳定正式 tag |
| Dear ImGui | v1.93.0（2026-10-14） | 否 | ocornut/imgui 官方 Releases；v1.93.0 为锁定版本本身 |
| stb | 提交 `6b5799b`（master HEAD，2026-11-19） | 否（提交源） | nothings/stb 无发布机制（README 确认 library list 最新 2026-11-19）；依 `002` 规格澄清 FR-012 以提交源最新提交为候选，当前锁定正是其 HEAD |
| cgltf | v1.15（2025-02-09） | 否 | jkuhlmann/cgltf 官方 Releases；v1.15 未过期，已是最新稳定版；v1.14 于 2026-04-25 |
| miniaudio | 0.11.26（2026-10-31） | 否 | mackron/miniaudio 官方 Release v0.11.26；CHANGES/README 均显示 0.11.26 为最新 |
| sdl3-zig | 提交 `aaa5868`（SDL 3.4.20，2026-11-03） | 否 | 当前锁定为该仓库 main 分支已知提交，绑定的 SDL 是官方 Release 3.4.20（2026-11-03），已核对 SDL 新版；按宪章 I 精确锁定提交 |

**决策（R1 完成）**:

| 依赖 | 结论 | 理由 |
| --- | --- | --- |
| jolt | 保持原样 | 已是上游最新稳定版 v5.7.0，门禁 G1/G2/G3（2026-11-26 实测退出码 0） |
| imgui | 保持原样 | 已是上游最新稳定版 v1.93.0，门禁 G1/G2/G4/G5 全通过 |
| stb | 保持原样（提交源） | 无正式 release 机制，锁定提交 `6b5799b`（2026-11-19）即稳定版 |
| cgltf | 保持原样 | 上游已是最新（v1.15），无需升级 |
| miniaudio | 保持原样 | 上游已是最新（0.11.26） |
| sdl3 | 保持原样 | 提交 `aaa5868` 绑定 SDL 3.4.20（2026-11-03 官方最新稳定 release） |

**Alternative considered**：选择"继续等更新"（例如预期中的新版本）——拒绝：按 FR-002 策略只采用正式稳定版且部署后必须通过全部验收门禁；当前锁定已满足。

## Rationale

- 以官方仓库 API/Releases 返回为准，不使用猜测版本或浮动分支引用（stb 与 sdl3-zig 按提交哈希固定，故以默认分支最新提交作为「最新版本」）。
- 依据 `002` 规格 Clarifications：预发布/候选版本不计入升级候选（FR-012）；按提交固定的来源取其最新提交。

## 未解决项

- 无。所有 6 项依赖的上游最新与当前锁定对比已完成；结论均为保持原样并给出理由。
