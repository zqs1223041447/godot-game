# v70 未分配路径对照

只运行当前源的固定90tick短场景，2.722秒、exit0、无ERROR；旧侧复用v69已保留结果，没有再次运行旧游戏。

完整观察为8,844,304字节，SHA256为bc9d401e91c165aafa195f81584f4391ec149b3f5a7aa6587c99b2e100e8f094，包含原伤害、状态、事件与随机观察，逐字节相同。保存文件仅把schema标记44改成45，其余原字节一致；这是未分配节点的兼容性证据，不是启用新节点后的伤害等价声明。

- [比较结果](comparison.json)
- [退出码与执行边界](run-result.json)
- [原始输出](current.log.txt)
- [压缩观察原字节](current.bin.gz)
- [当前原存档](current.save)
- [运行时源哈希](tested-inputs.json)
- [复现入口](run-current.py)

原始未压缩观察留在本地，Git保存无损gzip，避免提交重复大载荷。没有长测、画面或Windows帧率结论。
