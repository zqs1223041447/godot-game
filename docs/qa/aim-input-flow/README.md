# 共享瞄准修复：真实输入流程

基线 `95a6460296d416d552ed0079da8b1d0cfbb93edd`。复用已提交v094拥有权夹具和实际地图，不修改瞄准、冲刺或输入生产代码。

`attempt-01.log/json`：71检查、0失败。向实际Viewport注入鼠标移动／左键与物理键盘事件，使用存档中的冲刺绑定4，并由原Main处理。覆盖重合敌人且无移动时保持朝上、鼠标朝右、实际D键tick移动且鼠标朝上时冲刺向右、W＋D归一化175距离，以及破碎遗迹原墙体旁移动中冲刺的真实裁剪终点。逐次检查支付12魔力、冷却、0.6秒保护及键盘echo不重施，最后释放输入。

没有直接把期望方向传给施放函数；期望终点用原地形移动器校验，另核墙侧、身体不入墙与实际前进。headless视口使用原相机／屏幕变换；不是实体鼠标设备或自然游玩验收。

```bash
XDG_DATA_HOME=/tmp/godot-m1-aim-input-review XDG_CACHE_HOME=/tmp/godot-cleave-inward-cache \
INPUT_REPORT=/tmp/aim-input-review.json \
timeout 45 godot --headless --path . --script res://tests/aim_input_flow_test.gd
```

使用全新隔离用户目录。本批没有长矩阵、600秒检测、性能复测、模型工作或封包。代码与原始记录由相邻chain-ambush的manifest共同绑定。
