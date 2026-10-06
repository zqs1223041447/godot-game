class_name DamagePreview
extends RefCounted
## Read-only wording from the exact packets already used by casting.
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const TYPE_NAMES: Dictionary = {"physical": "物理", "fire": "火焰", "cold": "冰霜", "lightning": "闪电", "chaos": "混沌"}

static func points(components: Dictionary) -> String:
	var parts: PackedStringArray = []
	for type: String in Damage.TYPES:
		if float(components.get(type, 0.0)) > 0.0:
			parts.append("%s %.2f" % [TYPE_NAMES[type], float(components[type])])
	return "无" if parts.is_empty() else " + ".join(parts)

static func entries(cast: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not bool(cast.get("ok", false)):
		return result
	var packets: Dictionary = cast.get("packets", {})
	for role: String in ["parent", "child", "projectile", "direct", "secondary"]:
		if packets.has(role):
			result.append({"label": {"parent": "母箭", "child": "子箭", "projectile": "每枚投射物", "direct": "每次命中", "secondary": "独立爆炸"}[role], "packet": packets[role]})
	var bounces: Array = packets.get("bounces", [])
	if not bounces.is_empty():
		result.append({"label": "连锁首跳", "packet": bounces.front()})
		if bounces.size() > 1:
			result.append({"label": "第 %d 跳" % bounces.size(), "packet": bounces.back()})
	return result

static func summary(cast: Dictionary) -> String:
	if not bool(cast.get("ok", false)):
		return "伤害配置无效"
	var parts: PackedStringArray = []
	for entry: Dictionary in entries(cast):
		# A secondary packet is always frozen, but its effect still needs the item.
		if entry.label == "独立爆炸" and not cast.snapshot.effects.has("explode_on_flight_end"):
			continue
		var resolved: Dictionary = Damage.resolve(entry.packet, cast.snapshot.modifiers)
		parts.append("%s %.2f" % [entry.label, float(resolved.total)])
	var heading := "非暴击命中预估（未计敌方防御）：" if not cast.get("critical", {}).is_empty() else "命中预估（未计敌方防御）："
	return "此技能不直接造成命中伤害" if parts.is_empty() else heading + " / ".join(parts)

static func critical_lines(cast: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	if not bool(cast.get("ok", false)) or entries(cast).is_empty():
		return lines
	if bool(cast.get("hit_policy", {}).get("cannot_deal_critical_strikes", false)):
		lines.append("不能造成暴击（包括独立爆炸）")
		return lines
	var profiles: Dictionary = cast.get("critical", {})
	for role: String in ["primary", "secondary"]:
		if not profiles.has(role):
			continue
		if role == "secondary" and (not cast.get("packets", {}).has("secondary") or not cast.get("snapshot", {}).get("effects", []).has("explode_on_flight_end")):
			continue
		var profile: Dictionary = profiles[role]
		var prefix := "独立爆炸 · " if role == "secondary" else ""
		lines.append("%s暴击几率 %.1f%% · 暴击伤害 %.1f%%" % [prefix, float(profile.chance) * 100.0, float(profile.multiplier) * 100.0])
	return lines

static func leech_lines(cast: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	if not bool(cast.get("ok", false)) or entries(cast).is_empty():
		return lines
	var profiles: Dictionary = cast.get("leech", {})
	for resource: String in ["health", "mana"]:
		var profile: Dictionary = profiles.get(resource, {})
		var parts := PackedStringArray()
		for field: String in ["attack_fraction", "physical_attack_fraction"]:
			var fraction := float(profile.get(field, 0.0))
			if fraction > 0.0:
				parts.append("%s %.2f%%" % ["攻击" if field == "attack_fraction" else "物理攻击", fraction * 100.0])
		if not parts.is_empty():
			lines.append("%s偷取：%s" % ["生命" if resource == "health" else "法力", " · ".join(parts)])
	return lines

static func burn_lines(cast: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	var profile: Dictionary = cast.get("burn_profile", {})
	if not bool(cast.get("ok", false)) or not bool(profile.get("enabled", false)): return lines
	lines.append("点燃 %.1f 秒 · 非暴击、未计火抗" % float(profile.duration))
	for role: String in ["direct", "parent", "child"]:
		if not profile.get("roles", {}).has(role): continue
		var values: Dictionary = profile.roles[role]
		lines.append("%s每秒 %.2f 火焰 · 完整持续 %.2f" % [{"direct":"", "parent":"母箭：", "child":"子箭："}[role], float(values.dps), float(values.total)])
	var fire_dot_multiplier: float = float(profile.get("fire_dot_multiplier", 0.0))
	if fire_dot_multiplier != 0.0:
		lines.append("火焰持续伤害加成 %+.0f%%（已计入上方数值）" % (fire_dot_multiplier * 100.0))
	var burn_faster: float = float(profile.get("burn_faster", 0.0))
	if burn_faster != 0.0:
		lines.append("燃烧结算加快 %.0f%% · 已缩短持续时间，单次总量不变" % (burn_faster * 100.0))
	lines.append("同一目标不叠加；强点燃覆盖，同强度刷新。")
	var proliferation: Dictionary = profile.get("proliferation", {})
	if bool(proliferation.get("enabled", false)):
		lines.append("死亡扩散：半径 %.0f · 最多 %d 个目标 · 受墙体阻挡" % [float(proliferation.radius), int(proliferation.max_targets)])
		lines.append("保留原燃烧强度和剩余时间；扩散所得燃烧不再传播。")
	return lines

static func shock_lines(cast: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	var profile: Dictionary = cast.get("shock_profile", {})
	if not bool(cast.get("ok", false)) or not bool(profile.get("enabled", false)): return lines
	lines.append("感电 %.1f 秒 · 后续命中承受伤害提高 %.0f%%" % [float(profile.duration), float(profile.hit_damage_taken_increased) * 100.0])
	lines.append("闪电命中结算后施加；不追溯增强本次命中，不影响持续伤害。同强度刷新，不叠加。")
	return lines

static func assembly_line(packet: Dictionary) -> String:
	var trace: Dictionary = packet.get("assembly", {})
	if trace.is_empty():
		return ""
	var line: String = "固有：%s；附加：%s；附加效用 %.2f" % [points(trace.get("intrinsic", {})), points(trace.get("added", {})), float(trace.get("added_effectiveness", 0.0))]
	if trace.has("weapon"):
		var weapon: Dictionary = trace.weapon
		line += "；武器：%s〔(%.2f + %.2f) × (1 + %.2f) × 技能倍率 %.2f〕" % [points(weapon.contribution),
			float(weapon.profile.base.physical), float(weapon.profile.flat.physical), float(weapon.profile.increased.physical), float(weapon.coefficient)]
	return line

static func details(cast: Dictionary) -> String:
	if not bool(cast.get("ok", false)):
		return str(cast.get("error", "伤害配置无效"))
	var lines: PackedStringArray = ["逐次命中，不是总伤害或每秒伤害；最终还会读取敌方当前抗性。"]
	lines.append_array(critical_lines(cast))
	lines.append_array(leech_lines(cast))
	lines.append_array(burn_lines(cast))
	lines.append_array(shock_lines(cast))
	lines.append_array(trap_lines(cast))
	if cast.get("recipe", {}).get("delivery", "") == "melee" and cast.get("skill_id", "") == "basic":
		lines.append("普通近战攻击：距离 %.0f · 最多 %d 个目标；不发射投射物。" % [float(cast.recipe.radius), int(cast.recipe.max_targets)])
	if not entries(cast).is_empty() and bool(cast.get("hit_policy", {}).get("hits_cannot_be_evaded", false)):
		lines.append("命中不能被闪避；仍受距离、范围、墙体、免疫、护甲与抗性约束。")
	elif cast.snapshot.has("accuracy"):
		lines.append("上方是成功命中的伤害，未把命中率乘入；攻击命中值 %.0f，实际命中率读取敌方闪避。物理命中另受敌方护甲影响。" % float(cast.snapshot.accuracy))
	if cast.get("recipe", {}).has("_projectile_support_ids"):
		var pierce: int = int(cast.recipe.pierce)
		lines.append("每枚投射物穿透 %d 次，最多命中 %d 次；去返共享剩余次数，同相位同目标至多命中一次。" % [pierce, pierce + 1])
	if cast.skill_id in ["nova", "meteor", "cleave"] and cast.recipe.has("radius"):
		var base_radius: float = float(cast.recipe.get("base_radius", cast.recipe.radius))
		lines.append("%s范围：半径 %.2f → %.2f；面积 ×%.4f，半径 ×%.4f（面积倍率的平方根）。目标体型仍参与边界判定；覆盖人数取决于站位。" % ["扇形" if cast.skill_id == "cleave" else "圆形", base_radius, float(cast.recipe.radius), float(cast.recipe.get("area_multiplier", 1.0)), float(cast.recipe.radius) / base_radius])
	if cast.skill_id == "cleave":
		lines.append("近身扇区 %.0f 度；近战、攻击与范围标签生效。锻纹短刃的本地物理伤害参与本次斩击，白蜡长弓不参与。没有命中时也正常支付。" % rad_to_deg(float(cast.recipe.half_angle)*2.0))
	if cast.skill_id == "chain" and cast.recipe.has("hit"):
		lines.append("连锁最多 %d 个目标（含首个）；首段 %.2f，续跳 %.2f。已命中过的目标不重复，每个目标沿原配方递减基础倍率和附加效用。" % [int(cast.recipe.hit.bounce_count), float(cast.recipe.first_range), float(cast.recipe.followup_range)])
	if cast.skill_id in ["bolt", "frost", "shade_bolt"]:
		lines.append("现有减速时长 %.2f 秒。距离、生命周期与穿透分别结算；延长减速不等于新增异常状态。" % float(cast.recipe.slow))
	lines.append_array(spatial_details(cast))
	for entry: Dictionary in entries(cast):
		var packet: Dictionary = entry.packet
		var resolved: Dictionary = Damage.resolve(packet, cast.snapshot.modifiers)
		lines.append("%s：%s" % [entry.label, points(resolved.components)])
		lines.append(assembly_line(packet))
		if entry.label == "独立爆炸":
			lines.append("仅装备授予时触发；攻击/法术点伤与投射物辅助不作用于独立爆炸。")
	return "\n".join(lines)


static func spatial_details(cast: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	var recipe: Dictionary = cast.get("recipe", {})
	var snapshot: Dictionary = cast.get("snapshot", {})
	if recipe.has("parent") and recipe.has("child"):
		lines.append("母箭速度 %.2f · 子箭速度 %.2f；返回沿用各自速度。" % [float(recipe.parent.speed), float(recipe.child.speed)])
	elif recipe.has("speed"):
		lines.append("实际投射速度 %.2f" % float(recipe.speed))
	if recipe.has("speed") or recipe.has("parent"):
		lines.append("投射速度改变飞行快慢，不增加距离上限或存续时间。")
	var explosion: Dictionary = snapshot.get("explosion_recipe", {})
	var melee_basic: bool = cast.get("skill_id", "") == "basic" and recipe.get("delivery", "") == "melee"
	if melee_basic:
		explosion = {}
	if not melee_basic and snapshot.get("effects", []).has("explode_on_flight_end") and explosion.has("radius"):
		lines.append("独立爆炸半径 %.2f · 面积 ×%.4f" % [float(explosion.radius),float(explosion.get("area_multiplier",1.0))])
	if recipe.has("source_area_multiplier") or float(explosion.get("area_multiplier",1.0)) != 1.0:
		lines.append("范围增幅按面积计算；半径按面积倍率的平方根变化。")
	return lines


static func trap_lines(cast: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	var profile: Dictionary = cast.get("trap_profile", {})
	if not bool(cast.get("ok", false)) or not bool(profile.get("enabled", false)): return lines
	lines.append("脚下布置 · %.2f 秒后布防 · 触发半径 %.0f" % [float(profile.arming_seconds), float(profile.trigger_radius)])
	lines.append("保留 %.0f 秒 · 所有技能组共享 %d 枚；满额不消耗魔力或冷却。" % [float(profile.lifetime_seconds), int(profile.maximum_traps)])
	lines.append("放置时固定伤害与暴击；敌人靠近后释放一次，到期消失。触发需视线，范围增幅只改变爆发范围。")
	return lines
