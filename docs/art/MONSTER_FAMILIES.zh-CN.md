# 怪物美术家族与模板映射

本分支为技术样板留档，视觉方向待复核，尚未合入main。

本批新增掠行体、重甲守卫、裂隙守卫三个真实三维模型及各144帧图集；沿用已有crawler图集。当前11个怪物模板全部接到4个怪物家族，不是11套独立模型。未知模板仍保留原矢量fallback。

## 权威映射

运行入口：`ActorSpriteCatalog.enemy_key / enemy_tint`。下表为正常状态的非发光RGB调色，受击短闪另由ActorVisual处理；不改变伤害类型、碰撞或任何怪物规则。

| 模板ID | 游戏名称 | 图集家族 | 正常RGB调色 |
|---|---|---|---|
| crawler | 巡游体 | crawler | 1 / 1 / 1 |
| splitter | 裂殖巡游体 | crawler | 0.87 / 1 / 0.80 |
| skitter | 掠行体 | skitter | 1 / 1 / 1 |
| mist_skitter | 雾羽掠行体 | skitter | 0.78 / 1 / 0.92 |
| storm_skitter | 雷纹掠行体 | skitter | 1 / 0.94 / 0.72 |
| brute | 重壳体 | brute | 1 / 1 / 1 |
| brood_host | 孵化重壳体 | brute | 0.92 / 0.83 / 1 |
| ember_guard | 灰烬守卫 | brute | 1 / 0.80 / 0.65 |
| frost_guard | 霜纹守卫 | brute | 0.80 / 0.94 / 1 |
| chaos_guard | 蚀影守卫 | brute | 0.88 / 0.76 / 1 |
| rift_warden | 裂隙守卫 | rift_warden | 1 / 1 / 1 |

## 原始资源与可复查图册

每个图集为2048×1728透明RGBA、16列9行。每帧128×192；八方向E/SE/S/SW/W/NW/N/NE，每方向idle4、walk8、attack6，12帧/秒。运行按真实位移/已发生攻击选择动作，不由动画产生伤害。

| 家族 | 正式PNG与逐帧清单 | 足点 / 显示比例 | 方向图册 | 动作图册 |
|---|---|---|---|---|
| crawler | [图集](../../assets/actors/crawler_atlas.png) / [清单](../../assets/actors/crawler_atlas.json) | 64,142 / 0.64 | [八方向](contact-sheets/crawler-directions.png) | 逐帧清单 |
| skitter | [图集](../../assets/actors/skitter_atlas.png) / [清单](../../assets/actors/skitter_atlas.json) | 64,142 / 0.5 | [八方向](contact-sheets/skitter-directions.png) | [动作](contact-sheets/skitter-animation.png) |
| brute | [图集](../../assets/actors/brute_atlas.png) / [清单](../../assets/actors/brute_atlas.json) | 64,158 / 0.729167 | [八方向](contact-sheets/brute-directions.png) | [动作](contact-sheets/brute-animation.png) |
| rift_warden | [图集](../../assets/actors/rift_warden_atlas.png) / [清单](../../assets/actors/rift_warden_atlas.json) | 64,158 / 0.72 | [八方向](contact-sheets/rift-warden-directions.png) | [动作](contact-sheets/rift-warden-animation.png) |

这些联系图是原作者渲染后的检查拼图，带说明底色；运行图集保留真实透明度。原图册按字节复制，来源和SHA见 [图册清单](monster_contact_manifest.json)。实际模板色调与原家族图册区分记录。F8缩略图取南向idle原帧，仅移除空白并加透明边距，不重新设计或修改运行资产；未加模板调色的原图集缩略图不能当作完整战斗截图。

## 源文件与复现边界

三新模型与脚本在 `tools/art/skitter`、`tools/art/brute`、`tools/art/rift_warden`，均有`.gdignore`，不进入Godot自动模型导入。前两组输出相对脚本目录；rift_warden还接受显式`--out`。运行命令见各目录README。打包依赖前一步生成的144张帧图，仓库不将未复制的中间帧/预览假称现成文件。搬迁后交互打开`.blend`可能保留旧输出路径，先在Blender选择本机路径；Python导出入口会重设路径。本批没有重渲染，原PNG保持已验收SHA。

需要Blender4.3.2/Cycles CPU和Python/Pillow；跨Blender/渲染后端不承诺PNG字节完全一致。家族脚本只保存美术源，不参与游戏RNG。

## 尚待恢复的玩家装备外观

当前真实hero图集仍固定持杖。旧FantasyActors曾按装备base区分弓、剑和法器，这一能力尚未完整移入新图集；剑、弓、空手是后续同一hero模型的待办，应保身形和足点一致。本批不扩这项范围，也不把主角称为完成全部装备适配。

本批只改变表现，无新碰撞/技能/时序/怪物数值；没有Windows实机或帧率提升结论。

F8当前怪物缩略图使用独立 `tools/export_monster_reference_art.gd`。旧全量美术导出器仍是旧矢量入口，本样板不调用它；需要重建这一组图片时只用上述窄工具及其验证说明。
