class_name MapBossProfiles
extends RefCounted
## Map-only attack metadata. Damage remains the existing contact-component packet.
const Profiles=preload("res://scripts/monsters/telegraph_profiles.gd")
const DEFINITIONS={
	"garden_slam":{"id":"garden_slam","map_id":"old_garden","name":"近身震地","target_rule":"self_at_start","trigger_distance":140.0,"profile":{"radius":130.0,"windup_seconds":0.9,"recovery_seconds":1.7,"damage_multiplier":1.4}},
	"ruins_mark":{"id":"ruins_mark","map_id":"broken_ruins","name":"断垣落印","target_rule":"player_at_start","trigger_distance":420.0,"profile":{"radius":75.0,"windup_seconds":1.0,"recovery_seconds":1.5,"damage_multiplier":1.15}},
}
static func definition(id:Variant)->Dictionary:
	return DEFINITIONS[id].duplicate(true) if id is String and DEFINITIONS.has(id) else {}
static func profile_reason(profile:Variant)->String:
	if not profile is Dictionary:return "地图首领配置无效"
	var rule:=definition(profile.get("boss_attack_id"))
	if rule.is_empty() or profile.get("id")!=rule.map_id or profile.get("boss_id")!="rift_warden":return "地图首领攻击与地图来源不符"
	return "" if Profiles.resolve(rule.profile).ok else "地图首领攻击参数无效"
static func enemy_reason(enemy:Variant,attack_id:Variant)->String:
	if not enemy is Dictionary or definition(attack_id).is_empty():return "未知地图首领攻击"
	if typeof(enemy.get("id"))!=TYPE_INT or int(enemy.id)<=0 or typeof(enemy.get("root_id"))!=TYPE_INT or enemy.root_id!=enemy.id or typeof(enemy.get("generation"))!=TYPE_INT or enemy.generation!=0:return "地图攻击仅用于首领根实例"
	if enemy.get("template_id")!="rift_warden" or enemy.get("rarity")!="boss":return "地图攻击来源不是裂隙守卫"
	return ""
static func attach(enemy:Dictionary,profile:Dictionary)->Dictionary:
	var reason:=profile_reason(profile)
	if reason.is_empty():reason=enemy_reason(enemy,profile.boss_attack_id)
	if not reason.is_empty():return {"ok":false,"error":reason}
	if enemy.has("map_boss_attack_id"):return {"ok":false,"error":"首领攻击已经分配"}
	var result:=enemy.duplicate(true);result.map_boss_attack_id=profile.boss_attack_id
	return {"ok":true,"error":"","enemy":result}
static func for_enemy(enemy:Dictionary)->Dictionary:
	var id:Variant=enemy.get("map_boss_attack_id")
	return definition(id) if enemy_reason(enemy,id).is_empty() else {}
