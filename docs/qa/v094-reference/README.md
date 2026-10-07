# 源码批次94 环斩辅助：F8有限增量

本批只运行一次独立 `tools/encircling_cleave_reference.gd`：2.928秒、exit0，140个输入指纹前后相同。没有调用历史 `export_reference.gd`、collect、source coverage、Main、地图生成、战斗矩阵、随机装备、用户存档或素材生成器。项目显示仍为0.87.0；当前schema52、源政策49、装备词汇51。

## 真实输入与边界

- [实际Main结果](../v094-integration/main-result.json)为121项、0失败；[已购夹具](../v094-integration/owned-fixture.json)经真实正式商人购买裂刃斩8碎片、环斩4碎片，再以实际UID装配到第9技能组
- 导出器完整decode与验证schema52，核对两件宝石身份、组ID、主槽及辅助槽；只读接受原夹具到Model，复核当前ring和plain编译字段与Main原快照相同。装备、源天赋与宝石均来自原夹具，model零保存
- 两份预览读取真实DamagePreview与DamageResolver：未装环斩75.712、装后56.784，魔力12→15，半径95、冷却1.4秒保持；原基础系数与附加效用仍280%，没有重写为技能基础伤害
- 同次Main整圆探针有9个不同目标的真实direct命中收据，每目标一次。原样复用Main JSON的samples，避免二次Godot序列化改动小数末位；这是受控地图实体、资源与站位测试，不是自然游玩、掉落概率、DPS或长期平衡验收
- Main原检查完成后只追加了两处文字修改：新辅助定义及迁移提示把角度符号改为中文“度”；生产数值及编译输出未变。本导出读取最终文字和源码指纹，未声称重新执行Main覆盖该文字修改
- [导出stderr](export.stderr.log)保留Fontconfig缓存目录不可写的环境警告；没有Godot脚本错误。未为消除环境警告再次导出

## 合成与保全

新增环斩辅助及环斩规则两张卡，裂刃斩加入第六个可选辅助及新规则链接。九张当前schema说明仅把51改52；余烬旧卡仅把当前辅助数量22改23，其历史示例保持。其余3796张旧卡原字节保留，包括全部怪物、混抗规则、珠宝制作及四图路线卡。原混抗等旧章节的历史导出元数据保留，当前52/49/51合同由新环斩卡及当前schema目标卡说明。

catalog按原token合成，只改save_version、新support、新support示例、裂刃斩可选辅助数组与新环斩规则五条路径。84个原顶层段完整保留；全部其他技能示例、旧辅助、旧怪物、混抗、珠宝、四图、源树、中文字典及完整source coverage保持原字节。

只把唯一新原图 `assets/ui/grimoire/encircling_cleave.png` 同字节复制到F8 originals：1254×1254 RGBA，SHA256 `029dd3e73ca913cd91505f2d986f946d2b73b250caa63450b2f23d94bfe4dc51`。246张旧PNG、1份字体，连同art manifest、JS/CSS及历史source_inputs共254个受保护文件原字节保持。

[合成路径证据](catalog-format-preservation.json)、[聚焦复核结果](preservation.json)、[逐卡SHA256](card-sha256.json)、[导出输入指纹](export-input-sha256.json)及[本批输入清单](../../reference/source_inputs.v094.manifest.json)记录精确范围。最终聚焦检查通过：新增中文搜索词、全部本地链接、3854个唯一锚点、24个展示数值、实际Main来源、原始JSON token及资源字节。未重跑完整图鉴、战斗、原生F8视觉、截图、安装包或发布流程。

## 复核

```sh
python3 docs/qa/v094-reference/check-reference.py
python3 tools/build_reference.py --check
```

首次静态复核发现新卡输出使用合成前字典顺序，与最终catalog的排序不同；失败日志保留为first-order-check。仅改为读取最终catalog渲染HTML，随后重新静态核验，没有重跑Godot、Main或导出。

`run-export.py`只允许首次小片段导出；`merge-fragment.py`只接受c5690b9原catalog，防止重复插入。以上复核均不会运行Godot或重做Main。
