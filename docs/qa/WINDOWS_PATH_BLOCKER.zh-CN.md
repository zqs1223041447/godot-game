# Windows路径别名：修复与发布门槛

v0.14候选暂不发布。Windows专项在v0.13 / schema9发现：大写绝对别名指向同一文件，但BuildState的字符串键区分大小写，可能绕过未来版本写保护并跳过旧档备份。v0.14 / schema10保留同一逻辑，也受影响；其未来版本复现使用v11。

复现与人工fixtures位于分支 `codex/windows-save-validation-20261002`，初始证据提交 `fdcf3185758320ab2ccf66a0b416fa2d8fbf20c8`。基础Windows存档1326项通过、路径别名14项中3项失败；这不是普通默认路径加载的已知复现，也不应因此把别名边界称为安全。

受影响接点：`save_block_reason`、`_reject_load`、`load_build`成功解锁/迁移源记录，以及`save_build`迁移前后路径比较。`_backup_legacy_save`的原字节检查本身未被执行到。修复须统一Windows路径身份，并保留Linux大小写不同文件的区别。

先前Linux全量与原生UI结果仍是各自范围的证据，不能证明Windows别名安全。旧Windows导出候选已移出release目录并标为DO_NOT_PUBLISH。路径专项单点修复后，必须重跑Windows回归、Linux完整套件并重新导出，才解除此阻塞。

2026-10-02 已从 `fed036e05c2972f456d6ccf6110f3086f411ace3` 局部应用保存路径身份修复，保留 v0.14 的 schema10、v9 迁移和辅助注册表。Windows 专项在 v0.13 的 2058 项回归、v0.14 的 76 项别名回归均为零失败；证书库系统错误单独保留，`strict_log_clean=false`。详见[独立 Windows 记录](../windows-qa/SAVE_VALIDATION.zh-CN.md)。

主集成已在原生大小写敏感 Linux 文件系统补跑 81 项：未来版本保护、删除后的别名保护、历史 v1–v9 原字节备份、独立大小写文件与 Save As、恢复有效源后解锁全部通过。新 `tools/validate_save_paths_linux.py` 先探测实际 userdata，再执行反探针（退出78），最后才运行写入测试；所有写入位于唯一临时工程。最终全量、Windows 集成复验与新导出尚待收口，不能使用被隔离的旧候选。
