# Windows路径别名：发布阻塞

v0.14候选暂不发布。Windows专项在v0.13 / schema9发现：大写绝对别名指向同一文件，但BuildState的字符串键区分大小写，可能绕过未来版本写保护并跳过旧档备份。v0.14 / schema10保留同一逻辑，也受影响；其未来版本复现使用v11。

复现与人工fixtures位于分支 `codex/windows-save-validation-20261002`，初始证据提交 `fdcf3185758320ab2ccf66a0b416fa2d8fbf20c8`。基础Windows存档1326项通过、路径别名14项中3项失败；这不是普通默认路径加载的已知复现，也不应因此把别名边界称为安全。

受影响接点：`save_block_reason`、`_reject_load`、`load_build`成功解锁/迁移源记录，以及`save_build`迁移前后路径比较。`_backup_legacy_save`的原字节检查本身未被执行到。修复须统一Windows路径身份，并保留Linux大小写不同文件的区别。

先前Linux全量与原生UI结果仍是各自范围的证据，不能证明Windows别名安全。旧Windows导出候选已移出release目录并标为DO_NOT_PUBLISH。路径专项单点修复后，必须重跑Windows回归、Linux完整套件并重新导出，才解除此阻塞。
