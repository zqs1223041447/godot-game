# v0.55 锻纹短刃同源图鉴验收

结论：图鉴集中检查通过。1次Godot导出（12.875秒、exit0、stderr空）后，Python构建、确定性检查、短刃聚焦检查和JS语法检查均exit0。导出前后以及收口时的被依赖源码hash均相同。

## 本批范围

- 新规则卡：锻纹短刃1×3、本地W4、两本地tier及六族池、合法组合、当前自然掉落分布、既有六工艺、伤害/暴击定向16/40、偷取定向禁用、schema34迁移与原字节备份约定
- 5件目录校验的真实合法物品：白色、双本地T1最低/最高四缀金装、六族T1/T3顶值金装
- 95个实际编译命中包：B18、基础暴击5%/150%，明确排除职业三属性；原始包、后modifier普通值、零防御单次期望分开
- 全部非裂刃role本地贡献0，且包等于保留全局词缀但移除武器profile的真实编译对照；法术、普攻、龙卷与secondary仍取得全局暴击，资源保留全局属性
- 73个HTML数值逐项核对；所有旧卡ID和内部链接保留；所有本地图片存在
- 独立v54完整catalog经精确投影后语义hash保持；所有源树结构/execution和覆盖JSON保持；67旧PNG字节保持，1张短刃PNG与生产原图字节一致

这些是实际目录/编译器与离线页面的一致性证据；迁移卡直接运行纯迁移函数，不对玩家存档读写。原字节备份与失败事务由独立forgeblade_migration_test负责，不在图鉴内冒充实测。预算是单次成功命中的静态比较，不是实战DPS或完整配装平衡通过。

## 精确旧数据保护

基线来自独立 `v054-final-source-snapshot/docs/reference`，原catalog文件指纹和全部图像指纹保存在 `v054-reference-baseline.json`。快照不是用新目录重新生成的。检查先删除明确新增路径，再把有限字段恢复为其记录的旧值，最后对完整旧catalog计算语义SHA-256。

允许差异：7个新增内容/消费者元数据路径，30处追加资格元数据，18处当前schema、5处当前词汇、1处游戏版本、3处当前掉落profile、1个新增商店底材条目，以及76处裂刃本地消费者解释文本。解释文本逐条验证只将固定旧句换成固定新句，旧编译包/数值不改变；不是整段例子豁免。源树execution、源文本、几何与旧profile不在许可差异中。

`catalog-diff-review.json`列出全部141处叶级差异与分类。图鉴不会修改LUNA翻译、生产UI、战斗实现或其他测试。

## 命令与证据

```sh
python3 docs/qa/v055-reference/run-reference-checks.py --export
python3 docs/qa/v055-reference/capture-v054-baseline.py
python3 docs/qa/v055-reference/run-reference-checks.py
```

脚本拒绝覆盖既有证据；复查使用 `--check-prefix rerun-`。初次基线抓取器按数组位置比较商店库存，新增短刃位于旧固定物品之前，导致抓取器断言；调试保留 `baseline-capture-first-failure.*`，随后改为仅投影这个新底材条目，并验证全部旧库存逐字段相同。没有生产、Godot导出或聚焦套件失败。

- `godot-export-result.json` / `godot-export.*.log`：唯一Godot导出、exit和时长
- `export-source-sha256.json`：导出依赖快照
- `python-validation-results.json` / 对应stdout、stderr：四项聚焦检查
- `v054-reference-baseline.json`：独立旧数据与精确许可变更
- `catalog-diff-review.json`：旧目录差异审阅
- `summary.json`：结果、范围与明确未运行项目
- `final-artifact-sha256.json`：最终交付指纹

未运行600秒、历史全量或每版截图；不声称Windows硬件帧率，也不把离线静态检查写成完整浏览器交互验收。
