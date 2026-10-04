# 正式城镇界面接入

Root 修改既有城镇控件，不新建全屏菜单。三个生产文件：game_hud.gd、town_service_panel.gd、town_square_view.gd。

- 正式城镇、竞技练习、独立测试城镇分别显示，测试免费供应仅测试档可用。
- 地图增加档位选择与未解锁提示，费用和结算读取模型草稿；变更选项会禁用旧草稿的开启按钮。
- 待领奖励按钮读取模型 can_claim_normal_rewards 和 claim_reason；统一领取传 world_revision，界面不计算背包空间或生成奖励。
- 正式地图放弃确认说明入场费不退，测试模式继续旧确认。
- 纯 mock 控件检查16项通过：正常/测试切换、门禁、锁定档位、两种制图接口、待领与revision。首次夹具常量名 Panel 与引擎类重名导致解析失败，保留 controls-first-parse-failure.log，改夹具名后 controls.log 干净退出0。
- 当前证据不覆盖真实后端存档事务或 Windows 原生操作；这些留给同批整合路径，不冒充已有验证。
