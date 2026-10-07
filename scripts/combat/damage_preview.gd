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
	if bool(cast.get("penetration_profile", {}).get("enabled", false)):
		heading = "非暴击命中预估（零抗性、零护甲目标，含穿透）：" if not cast.get("critical", {}).is_empty() else "命中预估（零抗性、零护甲目标，含穿透）："
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
	if bool(cast.get("penetration_profile", {}).get("enabled", false)):
		lines.append("上方命中预估按零抗性、零护甲目标计算，已计入穿透；分量算式另列防御前数值。")
	lines.append_array(critical_lines(cast))
	lines.append_array(leech_lines(cast))
	lines.append_array(burn_lines(cast))
	lines.append_array(shock_lines(cast))
	lines.append_array(freeze_lines(cast))
	lines.append_array(trap_lines(cast))
	lines.append_array(inward_pull_lines(cast))
	lines.append_array(conversion_lines(cast))
	lines.append_array(penetration_lines(cast))
	lines.append_array(precise_technique_lines(cast))
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
		lines.append("%s范围：半径 %.2f → %.2f；面积 ×%.4f，半径 ×%.4f（面积倍率的平方根）。目标体型仍参与边界判定；覆盖人数取决于站位。" % ["周身" if bool(cast.get("encircling_cleave_profile", {}).get("enabled", false)) else "扇形" if cast.skill_id == "cleave" else "圆形", base_radius, float(cast.recipe.radius), float(cast.recipe.get("area_multiplier", 1.0)), float(cast.recipe.radius) / base_radius])
	if cast.skill_id == "cleave":
		lines.append_array(encircling_cleave_lines(cast))
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


static func inward_pull_lines(cast: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	if not bool(cast.get("ok", false)) or not bool(cast.get("area_impulse_profile", {}).get("enabled", false)): return lines
	lines.append("命中牵引至爆发圆心，受墙体与怪物分离影响；不改变伤害或触发半径。")
	return lines


static func conversion_lines(cast: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	var profile: Dictionary = cast.get("conversion_profile", {})
	if not bool(cast.get("ok", false)) or not bool(profile.get("enabled", false)): return lines
	if int(profile.get("version", 1)) == 2:
		var requested := PackedStringArray()
		var effective := PackedStringArray()
		for element: String in ["fire", "cold", "lightning"]:
			if profile.requested.has(element): requested.append("%s %.0f%%" % [TYPE_NAMES[element], float(profile.requested[element])*100.0])
			if profile.effective.has(element): effective.append("%s %.2f%%" % [TYPE_NAMES[element], float(profile.effective[element])*100.0])
		lines.append("物理转化请求：" + "、".join(requested))
		lines.append("实际分配：" + "、".join(effective) + "；保留物理 %.2f%%" % (float(profile.physical_fraction)*100.0))
		if bool(profile.normalized): lines.append("总请求超过100%，按比例分配，天赋选择顺序没有先后优先。")
		lines.append("转化部分适用物理与目标元素增伤，每条仅计一次。")
		if "physical_focus" in cast.get("support_ids", []): lines.append("物理专注对各转化部分：×1.20 ×0.80 = ×0.96。")
		elif "fire_focus" in cast.get("support_ids", []): lines.append("火焰专注：转火部分×0.96，转冰与转雷部分仅×0.80。")
		return lines
	lines.append("%.0f%% 物理伤害转为火焰；转化部分同时适用物理和火焰增伤，每条仅计一次。" % (float(profile.fraction) * 100.0))
	if "physical_focus" in cast.get("support_ids", []) or "fire_focus" in cast.get("support_ids", []):
		lines.append("类型专注的两条独立效果均作用于转化部分：×1.20 ×0.80 = ×0.96。")
	return lines

static func penetration_lines(cast: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	var profile: Dictionary = cast.get("penetration_profile", {})
	if not bool(cast.get("ok", false)) or not bool(profile.get("enabled", false)): return lines
	var parts := PackedStringArray()
	for element: String in ["cold", "lightning"]:
		if profile.fractions.has(element): parts.append("%s抗性 %.0f 个百分点" % [TYPE_NAMES[element], float(profile.fractions[element])*100.0])
	lines.append("本次命中穿透：" + "、".join(parts))
	lines.append("从目标有效抗性扣除，最低-100%；不修改目标抗性，也不作用于持续伤害。")
	return lines

static func component_detail_lines(detail: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	var names := {"physical":"物理", "fire":"火焰", "cold":"冰冷", "lightning":"闪电", "chaos":"混沌"}
	var final_name: String = str(names.get(detail.type, detail.type))
	if not detail.has("parts"):
		lines.append("%s %.2f × (1 + %.0f%%) × %.2f = %.2f" % [final_name, float(detail.base), float(detail.increased) * 100.0, float(detail.more), float(detail.final)])
		lines.append_array(penetration_detail_lines(detail))
		return lines
	for part: Dictionary in detail.parts:
		var path := PackedStringArray()
		for source_type: String in part.lineage: path.append(str(names.get(source_type, source_type)))
		var label: String = "→".join(path) if path.size() > 1 else "原生" + "".join(path)
		lines.append("%s %.2f × (1 + %.0f%%) × %.2f = %.2f（防御前）" % [label, float(part.base), float(part.increased) * 100.0, float(part.more), float(part.before_defense)])
	lines.append("%s合计：防御前 %.2f · 防御后 %.2f" % [final_name, float(detail.before_defense), float(detail.final)])
	lines.append_array(penetration_detail_lines(detail))
	return lines


static func precise_technique_lines(cast: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	var profile: Dictionary = cast.get("precise_technique_profile", {})
	if not bool(cast.get("ok", false)) or not bool(profile.get("enabled", false)): return lines
	lines.append("精准技艺：命中值 %.2f / 最大生命 %.2f · %s" % [float(profile.accuracy), float(profile.max_health), "门槛成立" if bool(profile.condition_met) else "门槛未成立"])
	lines.append("本次攻击伤害额外提高 %.0f%%（已计入预估）" % (float(profile.attack_more) * 100.0) if bool(profile.get("attack_applies", false)) else "本次技能未获得精准技艺的攻击伤害加成。")
	lines.append("命中值必须严格高于最大生命；门槛未成立也不能暴击，此天赋不绕过闪避。")
	return lines


static func freeze_lines(cast: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	var profile: Dictionary = cast.get("freeze_profile", {})
	if not bool(cast.get("ok", false)) or not bool(profile.get("enabled", false)): return lines
	var times: Dictionary = profile.duration_by_rarity
	lines.append("霜锁：普通/魔法 %.2f 秒 · 稀有 %.2f 秒 · 首领 %.2f 秒" % [float(times.normal), float(times.rare), float(times.boss)])
	lines.append("冻结不刷新；解冻后 %.2f 秒不能再被冻结，所有施法共享。" % float(profile.immunity_seconds))
	lines.append("暂停自主移动与攻击进度，外力和持续伤害仍生效；不撤销已经发生的攻击。")
	return lines


static func penetration_detail_lines(detail: Dictionary) -> PackedStringArray:
	if not detail.has("penetration") or float(detail.penetration) <= 0.0: return PackedStringArray()
	return PackedStringArray(["有效抗性 %.2f%% · 穿透 %.2f 个百分点 · 本次按 %.2f%% 结算" % [float(detail.effective_resistance)*100.0,float(detail.penetration)*100.0,float(detail.resistance)*100.0]])


static func encircling_cleave_lines(cast: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var profile: Dictionary = cast.get("encircling_cleave_profile", {})
	if not bool(profile.get("enabled", false)): return lines
	lines.append("环斩覆盖 %.0f 度；命中伤害额外降低 %.0f%%，魔力消耗倍率 %.0f%%。" % [float(profile.arc_degrees), (1.0-float(profile.hit_multiplier))*100.0, float(profile.mana_multiplier)*100.0])
	lines.append("角度扩大不增加半径；上方面积倍率仅指范围词缀，每个目标最多命中一次。")
	return lines
