# v079 两个天赋中文名称的真实面板验证

结果：一次 focused Godot 运行通过，109 checks、0 failures，进程退出码 0，无 SCRIPT ERROR/ERROR，耗时 4.164 秒。

- 基线：2e25e4710d95464c63a48f1e5413be3eb95a2b0a；执行目录为恢复后的 v079-name-recovery
- 环境：Godot 4.6.3.stable.official.7d41c59c4，Linux headless
- 时间：2026-10-06T11:09:12.870483+00:00
- 启动：使用 root 在恢复树完成的统一 import；旧执行器 import 37996 的结果不可恢复，没有将其计为成功
- 隔离：/tmp/godot-m1-v079-search/recovered-vkj39g72 下独立 data/config/cache

## 实际覆盖

测试直接实例化现有 CanonicalPassivePanel，对真实 CanonicalGameState 调用 setup，接入场景树。没有模拟搜索函数。六次调用实际 LineEdit.text_submitted 信号，交替查找两个目标，保证每次查找前均选中另一个节点：

| 中文名 | 英文查询 | ID查询 | 结果 |
|---|---|---|---|
| 冰霜之心 | Heart of Ice | 8833 | 三种查询均选中8833，树节点名与详情标题为冰霜之心，居中原始坐标 |
| 雷霆之心 | Heart of Thunder | 56716 | 三种查询均选中56716，树节点名与详情标题为雷霆之心，居中原始坐标 |

树节点显示、详情原始ID、效果行及现有状态标记、hover均通过；11239「风舞者」与29049「神圣火焰」作为未修改对照保持正确。

在面板setup/显示阶段及每次查询前后，验证真实模型snapshot、revision、stats、combat snapshot、content epoch、changed信号、存档字节、保存次数、文件列表及全局RNG抽样序列不变。原始Data节点英文名、ID、坐标与源文件一致，查询后整个Data.nodes缓存字节及源文件SHA256不变。

本测试没有创建竞技场，未进行战斗、分配技能或全树分配；RNG结论仅涉及被测面板/模型可访问的全局RNG，不声称竞技场RNG已测。没有截图、旧全量汉化测试、版本schema变更或生产代码修改。

## 证据

- [测试源码](../../../tests/passive_name_corrections_test.gd)
- [完整合并stdout/stderr](search.stdout.log)
- [进程退出码](search.exit.txt)
- [命令、隔离目录、基线及输入SHA256](search-result.json)

全部11份记录输入执行前后SHA256一致。测试源码SHA256：65b79da556d129c84327caadc42b052acd1a0c7b5a711f21739fc3019f2aadc7。
原始树文件SHA256：9774a8ec1fe16199e775fe99a20853837ca8c7725c48dfcd9d6ee69646ff934f。
stdout SHA256：4d4c05964a2483170ed2b1847dc22430909b2e2de523e67db915efa70496d5a9。

重现时先确保同一完整树已完成资源import，再为本次运行准备唯一 /tmp/godot-m1-v079-search/<run> 的XDG目录，然后执行：

```sh
/usr/local/bin/godot --headless --path /workspace/scratch/a51485f153de/v079-name-recovery --script res://tests/passive_name_corrections_test.gd
```

这是一项特定显示/搜索回归，通过不等同于全项目、原生图形或Windows实机验收。
