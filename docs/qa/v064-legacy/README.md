# v64 未分配节点兼容

同一外部 harness 先运行已冻结 v63，再运行 v64，各独立 XDG。各90 tick，仅把序列化构筑版本39/40这一身份字段移出比较；所有 stats、角色/怪物资源、弹体、命中/暴击/燃烧/感电/偷取、死亡奖励、实际掉落 RNG、存盘计数与JSON内容完整比较。

观察流8,844,304字节完全相同，SHA256 bc9d401e91c165aafa195f81584f4391ec149b3f5a7aa6587c99b2e100e8f094。实际磁盘文件仅version token改变，其余原字节相同。包含真实玩家与怪物短燃烧、物理入伤、主动施法、普攻与至少三次根怪结算。没有基准提速或Windows硬件结论。

两次均首轮exit0，无脚本错误。run-results.json保存命令/耗时/脚本SHA；对应inputs标明真实加载的生产文件。原bin留本地，Git保存mtime0 gzip，解压后SHA与comparison.json核对一致。
