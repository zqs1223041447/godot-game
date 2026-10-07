# 已撤回的冗余profile候选

结论：不纳入游戏生产。最后一次检查后，`scripts/mechanics/defense_rules.gd`已恢复eaf298a原字节，SHA256 `a4d88c005dfd27fe6408e86ea9b96a34fe01c786c24c8965113dd20498224226`。所有scripts/assets/scenes/data/project.godot与该基线相同；不改变版本、存档、F8资料或画面。

## 实际结果

复用已完成、有效的clean基线，只运行候选20帧余烬和4帧无燃烧。两个候选进程均exit0，无ERROR。逐帧完整观察、最终完整观察、原保存字节全部相等。独立纯规则58671项通过，含58611次完整typed-byte比较，验证错误优先序、类型、负零、别名和特殊参数fallback；没有微基准。

| 场景 | 原mean / median / p95 / peak ms | 候选mean / median / p95 / peak ms |
| --- | --- | --- |
| 余烬20帧 |179.541 /151.529 /831.212 /831.212|171.350 /151.118 /811.997 /811.997|
| 无燃烧4帧 |77.687 /76.944 /83.316 /83.316|80.203 /79.371 /89.254 /89.254|

余烬均值-4.56%，中位-0.27%，首峰-2.31%；未触及修改分支的无燃烧控制均值+3.24%，峰+7.13%。这是同一次有限前后样本，不足以支持主峰显著改善，且首峰仍超过800ms，因此按预设门槛撤回，不加样追求更好数字。p95采用原harness的索引算法，小样本20帧的p95恰是峰值，不把它当可靠总体尾部估计。

首峰是342命中、100燃烧、100怪物、0击杀；不能以场景名ember_deaths把峰值归因死亡队列。控制场景保100实体及攻击，玩家保护和180弹体是受控压力夹具，不声称自然玩家每帧发180弹或Windows硬件FPS。

## 保全与复验

完整前后数字及每帧记录见comparison.json，命令退出码见run_manifest.json。相等的观察和保存已固定mtime gzip归档，SHA/原字节长度在comparison.json及原诊断observation-archives.json。原大bin/save仅留本地，未重复提交。

被撤回代码原文保留candidate-defense-source.gd.txt，可执行归档candidate_defense.gd仅移除class_name；withdrawal-proof.json记录可逆变换和SHA。已经执行的原纯测试保存为../v095-rules/test-as-executed.gd.txt；当前测试入口仅把Current preload改为该归档候选，未来复跑输出改到隔离user路径，避免覆盖已验记录。此两处迁移经过静态逆变换验证，没有再次运行规则测试。

run.py是实际候选采样记录脚本，要求候选生产SHA并拒绝覆写现有结果。生产已经撤回，不能在当前main直接运行它并把基线当候选；若需复验，应另建隔离工作树使用归档候选/原SHA。这不构成自动追加采样指令。
