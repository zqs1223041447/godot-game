# v106 美术资料与源码集成

基线e2fa6db。本批仅本地保存与开发分支备份，暂停main整合，等待视觉方向复核；检查通过不等于最终美术认可。

运行变化仅ActorSpriteCatalog的三家族定义、11模板映射/色调，以及ActorVisual的怪物色调；主角受击闪色保留v105原值。Main、模型、碰撞、战斗、RNG、存档与经济未改。

## 复用已过检查

原验证worker完成2,359项有效源/像素检查及2,307项Godot检查，共4,666项；后续恢复hero旧hurt只有5项静态断言与依赖parse，未重跑4,666项。初次manifest字段名假设失败、受影响Rift重试和原始输入均保留在相邻QA目录。集成者按清单核当前源/资产SHA一致，不再做导入、战斗或长测。

Root在新进程实际Main进入断垣地图、移动并观察自动击杀，已查看不同家族；截图位于项目外 `monster-families-gameplay.png`。这是云Linux实际画面观察，不是Windows或FPS验收。截图不用作新的提交等待条件。

## 资料范围

- [家族说明](../../art/MONSTER_FAMILIES.zh-CN.md)精确列11模板、4家族、色调、PNG/逐帧清单及7张原方向/动作图册
- 三新建模目录均有`.gdignore`；Python输出相对脚本目录，Rift另支持--out。脚本只做AST与路径静态核对，没有重渲染
- F8仅11张怪物缩略图、美术manifest、雾羽/蚀影两卡占位图接线；只提取真实南向idle原帧，不染色、不缩放设计、不改运行PNG。数值catalog及卡片数据保持原字节；证据另见v106-reference-art
- 未恢复的hero剑/弓/空手外观明确登记为下一项，不并入本批

没有Windows包、Release或全F8资料导出。
