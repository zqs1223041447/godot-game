# v0.57 天赋中文显示兼容检查

本测试只补充 `tests/source_tree_localization_test.gd` 的状态与交互空白。既有测试继续负责全量 3,390 个源记录、6,981 次词条出现、译文数值与术语检查；这里不重演这些全量语义检查，也不重跑战斗、燃烧消费者或长场景。

## 运行

父线程完成本工程唯一一次共享首次导入后，运行：

```sh
python3 docs/qa/v057-compatibility/run-focused.py
```

可以用 `GODOT_BIN` 指定现有 Godot 4.6 引擎。runner 不执行导入；没有 `.godot/global_script_class_cache.cfg` 时直接拒绝。每次创建唯一 `/tmp/godot-m1-v057-compat.*`，将 XDG data/config/cache 分开隔离。GDScript 再核验 Linux、XDG 前缀和实际 user data 归属，验证前不打开任何存档。所有场景/构筑存档都落在该隔离目录，主存档名为 `v057-localization-compatibility.json`。

GDScript 有 45 秒失败保护，runner 有 60 秒进程保护。退出码 78 表示环境隔离或首次导入前置条件不满足。脚本错误、缺少完成摘要、非零失败数、只读阶段不足、任何输入文件变化均不能报告通过。runner 保留唯一命名的日志和 JSON 证据，记录实际命令、时长、退出码、检查/阶段数量及生产文件哈希，不覆盖历史运行。

## 明确断言

- 使用真实 `main.tscn`、HUD 和 `CanonicalGameState`，保留真实 arena RNG 与独立 critical RNG。场景处理和物理处理被关闭，因此测试不推进战斗；另检查全局随机序列和角色资源、run revision、发射数/伤害累计均不变
- 初始 fixture 沿 class 4 的真实可达路径分配 Dirty Techniques 和 Holy Fire，两类实际 stats 均为非零。所有 fixture 先通过完整 `CanonicalBuildRules.reason`，再保存到隔离档。路径 fixture 直接安装的是已验证的前置状态，不宣称逐步重演分配事务；既有 v53/v54 测试覆盖完整分配/退款及消费者
- 打开已分配中文树、单击与悬停、中文名/大小写英文名/原 ID 搜索、空与无结果搜索、升华/扩展/返回主树、切换火焰和魔力专精、关闭再打开，逐阶段比较 canonical snapshot 和 revision、实际 stats、compiled combat snapshot、content epoch、changed 信号次数、存档原字节、save 尝试/成功计数、文件列表及三类 RNG
- 以原英文 JSON 为独立图 oracle，核对标准树、一个真实升华和扩展分区的 source ID、坐标和边端点；主树必须保持 2,387 节点与 2,697 边，避免只改分区变量而仍显示旧图的假通过
- 3 个 faster 节点（11364/43684/59766）与 8 个 Fire DoT 节点（4713/5916/13559/31462/54396/2550/11924/29049）各自使用合法已分配前置路径，核对真实 model.available、UI 分配按钮、canvas 状态及逐条标签都认为可以分配，无错误“暂未实装”标记
- Deadly Draw 48823 在当前 class 4 受支持可达路径中没有可达邻点；使用已有合法构筑验证 partial 显示、实际 available/UI 禁用、仅未支持的一行加标记以及 UI/直接命令拒绝，不宣称已经满足邻接前置
- 火专精 11505:36313 使用同组已分配 Holy Fire 前置，检查该 effect ID 对应的 dropdown 行精确文本、单个标记、disabled 状态及直接 canonical allocate 拒绝。专精节点可能因另一个完整选项而可分配；不要求整个节点 available=false，不强留 disabled 选项、不调用可能分配其他合法选项的 UI 按钮
- 专精 picker 保留原 effect ID 和完整源词条数；程序切换选项不会保存专精，允许生产逻辑自动回到合法选项。火专精的已支持倍率行与未支持持续时间行仍分别显示
- 修改 `line_status` 返回的 grants 数组、grant 内层字典、missing_consumers 数组与布尔字段后，再次读取缓存必须恢复原值，后续显示不能被污染
- 全流程后 `Data.nodes()` 的原 ID、英文名称/Stat、专精 ID 和源坐标保持序列化字节一致，原英文源文件字节不变。runner 另外检查整个 scripts/data/scenes 和 project.godot 的生产输入哈希

## 验证状态与范围

父线程完成共享首次导入后进行了首轮定向运行，证据保留为 `evidence-1eyhp12y.json` 和 `compatibility-1eyhp12y.log.txt`：427 checks、4 failures、18 个只读阶段。四项失败是测试夹具前提不成立：Deadly Draw 没有受支持可达邻点；强制选择 disabled 火专精后，生产逻辑合法回退，导致三项“仍选中/详情文本”断言不成立。

现仅修正上述夹具：Deadly Draw 改用已有合法构筑；36313 按具体 dropdown 选项核验并只直接调用其拒绝命令。没有为满足测试改生产交互；修正后应恢复 19 个只读阶段，待父线程只重跑这一受影响集合。完整词条语义测试已通过，未要求重复执行。实际重跑结果以同目录新增 `evidence-*.json` 和对应日志为准。

本测试不改变 schema34、SourceTree 当前执行策略33、源数值或图结构，不验证所有战斗消费者，不产截图，不证明字体覆盖、视觉布局或 Windows 原生运行效果。
