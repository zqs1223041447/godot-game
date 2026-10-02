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
	return "此技能不直接造成命中伤害" if parts.is_empty() else "命中预估（未计敌方防御）：" + " / ".join(parts)

static func assembly_line(packet: Dictionary) -> String:
	var trace: Dictionary = packet.get("assembly", {})
	if trace.is_empty():
		return ""
	return "固有：%s；附加：%s；附加效用 %.2f" % [points(trace.get("intrinsic", {})), points(trace.get("added", {})), float(trace.get("added_effectiveness", 0.0))]

static func details(cast: Dictionary) -> String:
	if not bool(cast.get("ok", false)):
		return str(cast.get("error", "伤害配置无效"))
	var lines: PackedStringArray = ["逐次命中，不是总伤害或每秒伤害；最终还会读取敌方当前抗性。"]
	for entry: Dictionary in entries(cast):
		var packet: Dictionary = entry.packet
		var resolved: Dictionary = Damage.resolve(packet, cast.snapshot.modifiers)
		lines.append("%s：%s" % [entry.label, points(resolved.components)])
		lines.append(assembly_line(packet))
		if entry.label == "独立爆炸":
			lines.append("仅装备授予时触发；攻击/法术点伤与投射物辅助不作用于独立爆炸。")
	return "\n".join(lines)
