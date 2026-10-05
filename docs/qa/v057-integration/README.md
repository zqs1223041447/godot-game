# v57 汉化集成准备

- 基线：v56 386f465a7dd929836c3def3091a58939a90f1e36。
- LUNA：bfbc009167c1ce2b0fece3365d3ad1c2e723e5be，4个原提交通过双亲merge保留作者和轨迹。
- 当前仅准备阶段；最终主动/被动条件语义补丁和root复审待完成，尚不视为可发布。
- 原始英文树、ID、图结构、执行器、schema34不变。SourceTree当前语法策略33属于现有版本分层，未硬改为34。
- 映射JSON单独加入Godot include_filter；原目录3份原始资料继续逐路径排除，包验证器禁止该目录除唯一映射以外任何条目。
- 官方过滤说明：https://docs.godotengine.org/en/4.6/tutorials/export/exporting_projects.html
- 字体全量缺字重新基于v56字体计算；不会只补LUNA最后一次差量，原字形/度量保持。
- 后续一次集中运行汉化覆盖与真实模型/存档/RNG只读兼容，不重复历史战斗集合或600秒。
