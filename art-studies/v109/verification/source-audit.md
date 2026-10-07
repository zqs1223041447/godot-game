# v109 独立行走样板：来源与可搬迁性审查

审查日期：2026-10-07 UTC。基线为 `fc2cdbb817abf24ac5b6d7a5c849b3d3c4087c08`。本记录保存对原 `art-work/v109-walkable-study` 已完成的只读观察；写入本记录时没有重新扫描35项输入，也没有重跑27项headless或74项资产检查，没有导入或启动Godot。

## 结论

原运行资源完整，没有发现绝对workspace运行依赖，可整理为独立可搬迁项目。需补齐自包含的资产复验依据、字体许可、已纠正的环境作者记录，并说明首次资源导入前置。完整机器缓存、重复blend、ZIP和原下载集不是独立运行项目的必需内容。

`project.godot` 指向 `res://study.tscn`；场景、`study.gd`、`player.gd`、`study_overlay.gd` 均使用项目内资源。`run.sh` 由脚本自身位置计算根目录。manifest的30层文件全部存在，20个阻挡对象保留21个独立多边形，原目录无symlink。

运行代码直接使用 `screen_pixel` 碰撞点、`foot_screen_pixel` 与 `sprite_offset_pixel`，没有套用manifest的0.65相机换算。原环境光影与物件互遮挡已烘焙，不能把这些层声称为可任意移动或删除的独立物件。人物只切换原母图的8方向静态idle区域，不构成行走动画验收。

## 可复用的既有证据

- 对原 `qa/input-sha256.json` 的一次只读SHA检查已完成：35项全部存在并匹配；它覆盖资产与出处输入，不覆盖全部代码或后来的归档副本
- 原 `qa/headless-verification.json` 与 `qa/headless.log` 记录27项、0失败；原 `qa/asset-verification.json` 与 `qa/assets.log` 记录74项、0失败。本轮仅读取这些结果
- 日志中的引擎版本是Godot 4.6.3.stable.official.7d41c59c4
- hero/font已与fc2cdbb的v108归档做过字节比较，二者分别一致。普通复制可在Git中共用相同blob，不需symlink
- 原handoff仍记录原生画面待父任务检查、未截图、未测FPS。后续观察应另写证据，不能改写历史handoff后声称原检查覆盖了这些项目

关键原输入SHA：

- hero：`63bcf0d01273f448c44d642f8f3a63e54742762c7bc3119707f391ef2328e4ea`
- font：`8e84c0eaf389a86424df39a7e162519de7bd63297fc97679089a4d2a522e5ccc`
- runtime manifest：`3de399ca6b7e2d84298076f1c2b231a759afe5a6f4b049b6052767f47bc8ea4c`

## 测试路径与首次启动

`tests/verify_study.gd` **没有跨目录源文件依赖**。它预载入 `res://study.gd`，随后使用同一项目的全部运行资源；前置是Godot、已完成资源导入，以及存在且可写的 `qa/`。运行时会覆盖 `qa/headless-verification.json`，所以需要重跑时应使用临时检出或另选结果路径，避免覆盖原始证据。

原 `tests/verify_assets.py` 依赖两个同级源目录：`v108-professional-environment/exports` 提供manifest与30层PNG，`v108-quality-scene/assets` 提供hero与font。它还需要Python 3、Pillow和可写的 `qa/`，并会覆盖资产报告。建议使用冻结的原SHA作为独立归档的默认比较依据，原目录只作为可选的额外比较，另留原已执行源码。改写后的入口不能冒称本轮已重跑。

`run.sh` 的路径可搬迁，但脚本只启动Godot，**不执行首次导入**。省略 `.godot` 缓存后，先用Godot 4.6.3编辑器打开独立 `project.godot`，等导入完成，再运行 `bash run.sh`。可选CLI导入形式为 `godot --headless --editor --path PROJECT_DIRECTORY --import`；这条命令是使用说明，本轮未执行。Windows可直接在Godot打开项目，不依赖Bash或symlink。

应保留32份源资源 `.import` 设置和各脚本 `.gd.uid`。`.import` 中指向 `.godot/imported` 的路径是可重建缓存目标，不是必须打包的外部源文件。省略 `.godot`、`.runtime-home` 和空编辑器目录。

## 许可、作者和源映射

原v109的 `assets/environment/SOURCES.md` 仍把Grass Bermuda 01列为Rico Cilliers和Rob Tuytel。已检查的fc2cdbb归档在 `art-studies/v108/environment/SOURCES.md` 中更正为Rico Cilliers，应沿用该记录。

原v109没有随字体附OFL；基线的 `art-studies/v108/godot_preview/assets/OFL-NotoSansCJK.txt` 可直接复用。人物来源记录为基线 `art-studies/v108/character-provenance.json`。环境资产出处所记CC0、字体SIL OFL和生成人物的来源应分别说明，不能把整个项目统称为CC0。

原SOURCES引用的 `asset-download-audit.json` 未随原v109文件夹提供。可补基线 `art-studies/v108/environment/asset-download-audit.json` 这份小审计，或给出明确且可访问的基线记录位置，无需复制原下载素材集。

原35项输入清单包含旧SOURCES的SHA。归档采用纠正版SOURCES后，保留原输入清单作历史证据，另建归档manifest记录实际文件与新SHA，并记录原文件到归档文件的对应关系。不要改写历史清单以掩盖文档修正。

## 最小保全范围

- 独立项目入口、场景、三个运行脚本、run.sh、README、脚本UID
- 两份人物/字体原文件、30张环境PNG及其import设置、runtime manifest、DELIVERY_FROZEN
- OFL、纠正版环境出处、人物来源和下载/源映射记录
- 测试脚本、原已执行源码、原input-sha256、handoff、两份通过报告及对应日志
- 新归档的实际文件清单和来源对应记录

父任务在15:52 UTC告知：项目已放到 `../godot_preview`，资产检查已改为冻结原SHA加可选原目录，原已执行测试源码保存到 `qa/original-test-sources`，OFL、纠正版SOURCES和审计已补，运行GD、场景与原27检查仍保持原字节。这些是父任务提供的归档进度，不是本审查再次验证后的结论。

本审查没有重跑Godot、截图、性能、动画、导出或主游戏检查，没有提交或推送。核心读取及静态SHA观察完成后，一次可选补充读取遇到执行器transport断开；本记录未将未完成读取算作证据。
