# Contract: 依赖声明（build.zig.zon）

本契约约束升级后 `build.zig.zon` 中直接依赖的声明形式。它是本功能唯一需要改写的依赖源文件。

## 声明结构

每一项直接依赖必须包含：

```zig
.<name> = .{
    .url = "<不可变的 tag 或提交 URL>",
    .hash = "<由 zig fetch 计算的固定内容哈希>",
    .lazy = true,   // 可选依赖保持 lazy
},
```

## 规则

1. **不可变引用**：`.url` 必须指向确切的 release tag 或提交 SHA；禁止分支名、`latest`、通配符或范围版本。
2. **固定哈希**：`.hash` 必须来自 `zig fetch --save <url>` 的输出；禁止手工推测或从本地缓存复制。
3. **lazy 语义保持**：原本标记为 `lazy` 的依赖（jolt、cgltf、stb、imgui、miniaudio）在升级后必须继续为 `lazy`；`sdl3` 为非 lazy，保持不变。
4. **集合不变**：不得新增或删除直接依赖键；升级仅改变现有项的 `.url` 与 `.hash`。
5. **工具链不变**：`.minimum_zig_version` 必须保持 `"0.17.1"`；`build.zig` 中的 `@compileError` 校验不得放宽。

## 获取新哈希

```sh
# 在仓库根目录执行，URL 为候选升级的精确 tag/提交
zig fetch <url-with-new-version>          # 只输出内容哈希，不改写文件
zig fetch --save=<name> <url-with-new-version>   # 直接写入 build.zig.zon
```

不带 `--save` 的 `zig fetch` 只输出哈希而不改写文件，便于比对后再写入。写入后需确认 `build.zig.zon` 中无浮动引用。

## 契约验证

- 静态检查：`.dependencies` 键集合与升级前一致；所有 `.url` 为不可变引用；所有 `.hash` 非空且为 `zig fetch` 产物。
- 动态检查：删除本地 `zig-pkg/` 缓存后执行离线构建；成功即证明哈希与 URL 在干净环境可复现。
