# 正式宝石购买与回收

v0.44.0使用现有校准碎片和原26种可执行宝石，不增加宝石等级、品质进程、付费刷新或额外钱包。

## 可见服务与预算

正式城镇宝石商人根据GemCatalog实时列出10种主动、16种辅助。主动每颗8碎片，辅助每颗4；背包所选一颗回收1。预算为本游戏初版，非最终平衡结论。地图三档无词缀净奖励均4，最多加词缀奖励4；购买回收净损失3或7，不存在买卖套利。测试城镇保持免费全部供应和独立存档，不能向正式档转移实例或回收所得。

只回收真实背包中的skill_gem或support_gem，要求目录完整合法、1级0品质。技能主孔、辅助孔和待安置位置拒绝。无需拥有两颗才可回收；确认明确只消耗选中UID。同定义的另一个UID不受影响。

## 一次原子交易

列表和回收按钮读取轻量元数据，不创建报价、不抽随机数、不复制完整构筑、不读存档。点击具体商品或回收按钮后，模型完整校验当前构筑和候选，保存完整快照以及原文件回执，只向UI返回不含候选的报价句柄。

购买先从候选扣除真实背包碎片，再寻1×1格，因此恰好消耗一整堆碎片可释放购买格；其余满包、注册数或序号上限失败不扣费。回收先移除所选UID，再合并或用释放的格子放入真实碎片；库存总量溢出和写盘失败全部拒绝。

确认时必须仍在正式城镇、相同model和world revision，完整构筑等于报价快照，磁盘原字节回执仍一致。随后走原Store完整验证、原子落盘、更新内存、一次changed。新UID只在成功候选中提交；购买和回收不增加工艺revision、不抽掉落/暴击/制作随机流。schema保持27。

选择变化、关闭面板、离城、切档、重新读取及成功交易清理旧句柄；句柄最多保留8个。执行尝试消耗该句柄，即使写盘失败也需重新获取报价，防止二次确认。外部字节被修改时不覆盖。

## 代码接口

- GemTradeRules.offers / quote：纯目录预算，无位置、磁盘或状态所有权
- CanonicalGameState.normal_gem_offers(path)、gem_recycle_info(uid,path)：菜单元数据
- gem_trade_quote(operation,target,expected_revision,path)：操作buy/recycle，目标定义ID/实例UID；返回handle、cost和materials字典
- execute_gem_trade(handle,current_target)、cancel_gem_trade_quote(handle)、invalidate_gem_trade_quotes()
- 主场景normal_gem_offers、normal_gem_recycle_info、normal_gem_trade_quote、execute_normal_gem_trade、cancel_normal_gem_trade_quote在模型API外增加城镇/世界修订门禁

前端复用宝石商人、原背包回收按钮及二次确认；主场景和模型分担各自权威，不在视觉层计算价格。
