# 美术源文件与搬迁运行

已交付运行PNG是验收基准，源码目录提供原始模型和生成/打包脚本。脚本以自身所在目录写出产物，不依赖原工作机的 `art-work` 目录。以下是未来重建说明；本次收口未执行渲染、未重写288帧。

环境为 Blender 4.3.2 / Cycles CPU，打包脚本另需 Python 与 Pillow。请在可写的源码副本运行，避免覆盖已验收文件；不同Blender或渲染后端不保证PNG逐字节相同。`.gdignore` 防止Godot导入建模目录。

## 主角

在 `tools/art/hero` 目录运行：

```sh
blender -b --python render_hero_atlas.py
python3 pack_hero_atlas.py
```

第一步调用同目录 `generate_hero.py` 并生成144张 `frames/hero_NNN.png`、`hero_manifest.json` 和模型；第二步读取这些新生成中间文件，输出图集/清单/帧表。初次重建不要使用需要旧清单的 `--repair`。源码仓库保存最终图集于 `assets/actors/hero_atlas.png`，对应清单名为 `hero_atlas.json`；重建结果不会自动覆盖运行资产。

## Crawler

在 `tools/art/crawler` 目录运行：

```sh
blender -b -t 4 --python generate_cairnback.py -- --all
python3 generate_cairnback.py --pack
```

生成144帧和 `atlas_metadata.json` 后再打包。`--test` 只有四帧，不能当完整图集；正式运行清单为 `assets/actors/crawler_atlas.json`。

## 地景

已保存的 `environment_native_preview.blend` 含最终refine结果。在 `tools/art/environment` 直接用此模型执行 `export_sprites.py`，会在该目录写三张透明PNG及生成清单。若从网格脚本重建，按该目录README执行 build→refine一次→export；不要对已refine的模型重复反转面。三个运行资源路径与 `dimensional_manifest.json` 的texture映射保持显式，不自动更新。

交互打开搬迁后的 `.blend` 时，Blender内嵌的上次输出目录可能仍为旧位置，请手动选择新输出位置。Python导出入口已显式重设路径。地面 `garden_ground.png` 是图像生成原始资产，不能由以上Blender模型重建；其来源与SHA在 `docs/art/generated_asset_provenance.json`。
