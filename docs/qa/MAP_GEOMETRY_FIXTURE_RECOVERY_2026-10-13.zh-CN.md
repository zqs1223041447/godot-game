# 地形集成测试夹具恢复（2026-10-13）

## 范围与环境

- 仅在 dot 当前本地环境执行，Godot 4.6.3；恢复来源 HEAD `0373f7f3aba2ff20aa9cfb122a03cbf4e81128d6`。
- 本项仅修改 `tests/map_geometry_integration_test.gd` 与 `tests/map_terrain_edge_test.gd`，没有修改生产代码。
- 共享工作区同时进行独立的贴墙追击与字体修复。本报告的测试结果是当时共享工作树结果，不能称为远端 HEAD 的独立完整回归。复验时生产 `scripts/world/map_geometry.gd` SHA-256 为 `94acc24a824152142384939dff946daea0af6849c10a076ae6e07e397fffa6cb`。
- 每个运行使用独立 `/tmp/godot-m1-*` 下的 XDG_DATA_HOME、XDG_CONFIG_HOME、XDG_CACHE_HOME，不接触用户存档。

## 原夹具失败复现

08:38 UTC，在修改这两个测试之前：

- map_geometry_integration：78 检查、6 失败，退出码 1
- map_terrain_edge：6 检查、1 失败，退出码 1

日志：`/tmp/godot-m1-geometry-baseline/output.log`、`/tmp/godot-m1-edge-baseline/output.log`。

失败原因及替代验证：

1. 当前新角色公开入口为正式城镇，旧测试直接假设竞技场。先断言安全城镇，再通过 `leave_normal_town` 建立原来的 normal 场景断言。
2. 展示快照新增 `dimensional_wall_indices`，不再与权威快照直接全字典相等。验证展示字段为合法、无重复的墙索引，去除唯一已知展示字段后仍比较全部权威字段。返城时同时断言墙覆盖为空、墙体为空、修订号递增及全部权威字段一致。
3. 现有探索墙高 1260，旧 1500 帧（25 秒）不足以让原速 50 的重壳体绕完。预算独立取 `(墙高 + 墙宽 + 400) / 50`，不随待测速度放宽；明确断言原速 50。逐帧检查身体合法、连续扫掠无碰撞、位移不超过 50/60，并保留必须越过墙端且接近玩家的最终断言。
4. 人工创建分裂根怪并直接调用 runtime.process_death 绕过地图出生登记；现有成员与奖励来源校验会正确拒绝其后代。改为公开 restart 恢复真实登记阵容，选择本身具有死亡分裂的根怪，真实伤害结算后验证死亡账本、预留后代数、尸体退场、所有后代合法且零经验/零奖励。另验证根怪只奖励一次、后代实际结算不增加奖励、重复根死亡不二次奖励。
5. edge 旧测试直接清空 admitted/defeated。删除直接篡改，改为验证公开 retry 后普通根怪登记数完整、死亡账本为空，再走原有返城保存入口。

## 修复后结果

08:40–08:42 UTC：

- map_geometry_integration：91 检查、0 失败，退出码 0
- map_terrain_edge：10 检查、0 失败，退出码 0
- 独立新 XDG 目录重复运行 integration：91/0、90/0，均退出码 0。检查数差异来自真实随机阵容所选根怪后代数量，并非跳过失败检查；每次均要求存在分裂根怪、后代数大于零且与真实预留数完全一致。
- 两测试 `git diff --check` 通过

日志：

- `/tmp/godot-m1-geometry-fixed/output.log`
- `/tmp/godot-m1-edge-fixed/output.log`
- `/tmp/godot-m1-geometry-repeat.L7ZZ6i/output.log`
- `/tmp/godot-m1-geometry-repeat.3vkRRU/output.log`

复验命令模式：

```sh
base=$(mktemp -d /tmp/godot-m1-geometry-check.XXXXXX)
mkdir -p "$base"/{data,config,cache}
XDG_DATA_HOME="$base/data" XDG_CONFIG_HOME="$base/config" XDG_CACHE_HOME="$base/cache" \
  godot --headless --path . --script tests/map_geometry_integration_test.gd
```

未打包、未导出 Windows 程序、未提交或写入远端。
