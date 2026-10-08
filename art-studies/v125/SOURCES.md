# 来源与许可

作者来源：Quaternius。以下均为此前已批准、已取得并核验的免费Standard包。本次只归档自行制作的渲染输出、自写脚本及必要记录；不上传原模型、纹理包或Blender场景，也没有新下载。

| 上游来源 | 已验证原包SHA256 | 本研究用途 |
|---|---|---|
| Modular Character Outfits - Fantasy [Standard] | c3468b18871cc8c8f05ab14df7712baf22cb9f389cbd870babf130e595187f70 | Female Ranger衣装与纹理的渲染来源 |
| Universal Base Characters [Standard] | fdbf1804c90dfc1ea03e992bff7da2dfd1a79318e13270a660180f9308455f40 | 女性角色头颈/眼眉及BuzzedFemale头发来源 |
| Universal Animation Library Standard | 18ff1a7215f4852b320203e8aaf02a1578b5c8eef9027fbaedfcedc7b85a3ac2 | 真实Walk_Loop、Jog_Fwd_Loop源动作 |

已记录的角色包官方入口：

- https://quaternius.itch.io/modular-character-outfits-fantasy
- https://quaternius.itch.io/universal-base-characters
- 作者网站：https://quaternius.com

三个包内许可证均明确标明 **CC0 1.0 Universal / Public Domain Dedication**。本目录保留原文：

- `licenses/fantasy-License_Standard.txt`
- `licenses/base-License_Standard.txt`
- `licenses/UAL_License.txt`

CC0说明：https://creativecommons.org/publicdomain/zero/1.0/

不把上述记录扩写成对作者其他版本/产品的统一许可判断。归档不包含上游原始包文件。

## 制作链

1. v123本地场景提供最终肩桥蒙皮、13个原网格及三套target rig、已核Walk目标动作
2. v124本地场景提供已核53→65重定向的真实Jog目标动作
3. v125只做一组离线80/20混合与单方向导出；几何、权重与旧动作不变

两个输入场景的确切SHA256在 `reports/trial-metadata.json` 的 `sources` 字段中，用于本地复现输入校验。原场景不在仓库中。

此归档的16张PNG为该制作链的作者制作渲染输出，与已完成v125候选帧逐字节一致。`reports/source-frame-hashes.json` 给出对应关系，不用缩略图或重新编码图片替代原帧。
