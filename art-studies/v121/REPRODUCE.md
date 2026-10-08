# 复现说明

## 环境与安全

Blender 4.3.2；Python 3 + NumPy + Pillow；Noto Sans CJK字体。Blender均使用 `--background --disable-autoexec`。只运行本目录自写脚本，glTF/BIN/贴图只作为数据读取；没有运行包内程序或新下载素材。

所有命令在本目录 `art-studies/v121` 执行。仓库只保存脚本、渲染图、报告与说明，**不含最终blend、work_sources、原ZIP或原模型/纹理**，不能仅凭仓库执行几何复验或重建。本次备份没有运行下列渲染/几何命令，也没有改动冻结图和模型。

## 校验已归档快照（不需外部素材）

```sh
sha256sum -c SHA256SUMS.txt
```

清单覆盖其自身以外的全部43个归档文件；局部 `.gitattributes` 保留两份原许可文本的CRLF换行和空格。历史技术报告及效果图按原字节保留，报告内的绝对路径是原制作环境记录。重新生成报告或渲染将改变快照哈希；先校验，再在独立副本中复现。

## 取得外部输入并建立工作副本

先从[SOURCES](SOURCES.md)列出的官方入口取得精确两个Standard包，放在仓库以外的目录。其文件名、字节数与SHA-256均列于来源说明和DELIVERY-MANIFEST.json；不能把不同版本的包静默当成同一输入。设置外部目录后，在独立工作副本中执行：

```sh
export V121_SOURCE_ARCHIVES=/absolute/path/to/external-character-archives
python scripts/prepare_sources.py
```

脚本必须取得 `V121_SOURCE_ARCHIVES`，会核对两原包SHA后以白名单方式只提取glTF/BIN/PNG/TXT数据、修复副本URI，并将 `reports/source-manifest.json` 的 `asset_paths` 重写为当前工作副本路径。归档中的该报告保留原机器路径，因此不能跳过这一步后直接重建。脚本不联网下载，不执行包内程序；新产生的 `work_sources`、blend与备份文件不属于公开备份白名单，禁止提交。

质量渲染使用随脚本保留的 `reports/environment-settings.json`，不必重新打开环境blend。原尺度合成另需要已有项目的 `art-studies/v118/qa/sparse-assembly.png`，SHA-256为 `95a571895b67878e0a7084dbd0ae08046a1245910ffda059e68e7686895af4fe`。两者与原角色包分开记录；没有再次打包原始模型或ZIP进备份。

## 从现有glTF工作副本重建

仅在需要重新构建、且上节工作副本准备完成后执行。`assemble_and_render.py` 会覆盖当前工作blend，后续命令会覆盖渲染和报告；先另存所需版本。若已有本机的有效工作副本和对应 `asset_paths`，无需再次下载或提取原ZIP。

```sh
blender --background --disable-autoexec --python scripts/assemble_and_render.py -- --assemble-only
blender --background --disable-autoexec ranger-sample.blend --python scripts/inspect_shoulder_surface.py
blender --background --disable-autoexec ranger-sample.blend --python scripts/finish_shoulder_and_render.py
python scripts/compose_comparison.py
blender --background --disable-autoexec ranger-sample.blend --python scripts/verify_final_sample.py --python reports/verify_geometry.py
python scripts/verify_source_clip.py
```

`--assemble-only` 跳过未修整状态的全部渲染。下一脚本完成一次小型静态内衬修整并输出最终质量图、原尺度角色与阴影。若输入场景已经有该内衬对象，它只重渲染而不重复新增对象。

渲染：Cycles CPU / 8线程；seed 121；关闭降噪、启用自适应采样，threshold .025；质量192采样，原尺度角色96采样，阴影128采样。输出8-bit RGBA PNG。质量图视域2.10m、1200 × 1200；实际图视域27m、1280 × 720；俯角均55°。不同Blender版本/硬件的像素哈希不保证一致。

## 冻结环境依赖

- 灯光/色彩来源：本目录相对路径 `../v111/source/modules.blend`（SHA见SOURCES；仅来源证据，重渲染使用已保存JSON）
- 技术合成背景：本目录相对路径 `../v118/qa/sparse-assembly.png`
- 合成脚本只读该1280 × 720背景；角色与阴影平移(70,190)源像素，脚底从(640,360)到(710,550)，scale=1；4倍最近邻只是旁侧检查窗
- 完整仓库中的合成脚本自动使用相邻v118背景；若单独搬迁此目录，设置 `V121_BACKGROUND` 为经SHA核对的同一背景文件绝对路径，不要用任意新背景冒充原环境对照
- 阴影alpha作0.8%底噪扣除，并依太阳方向估算平地投影范围后加24px边距。此为技术合成近似，不能替代游戏内遮挡测试

`inspect_environment.py`、`inspect_import.py`与 `build_delivery_manifest.py` 保留作初次处理溯源，不是校验归档的必要步骤。尤其不要对冻结归档运行清单生成脚本：它扫描本地生成文件，并会替换分组与哈希记录。仅校验已有最终blend时，可以运行 `verify_final_sample.py` 和 `reports/verify_geometry.py`，但这会重写报告，不会保存场景、改变模型或新增渲染。

本地输入/最终blend的哈希清单 `SHA256SUMS-local-only.txt` 未纳入仓库。外部原包精确SHA与备份分组见DELIVERY-MANIFEST.json；逐源文件哈希见历史 `reports/source-manifest.json`。本目录由上层 `.gdignore` 隔离，复现脚本不自动提交、推送或接入游戏。
