extends SceneTree
const Policy = preload("res://scripts/rewards/kill_reward_policy.gd")
class RarityHint extends RefCounted:
	var reads := 0
	func _to_string() -> String:
		reads += 1
		return "rare"
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)
func _initialize() -> void:
	var enemy := {"root_id":7,"map_spawn_key":"camp:7","rarity":"normal","xp_reward":12}
	var records := {7:{"spawn_key":"camp:7","reward_route":"standard"}}
	var before := var_to_bytes([enemy,records])
	check(Policy.resolve_route(enemy,true,records).route == "standard","Birth record selects standard")
	enemy.reward_route="untrusted_actor_hint"
	check(Policy.resolve_route(enemy,true,records).route == "standard","Actor hint cannot override admitted route")
	enemy.erase("reward_route")
	for route: Variant in ["future", "", null, 7, {}, []]:
		records[7].reward_route=route
		check(not Policy.resolve_route(enemy,true,records).ok,"Unknown/malformed route fails closed")
		check(not Policy.plan(str(route),enemy,true,false,59,true).ok,"Unsupported plan fails closed")
	records[7].reward_route="standard"
	check(not Policy.resolve_route(enemy,true,{}).ok,"Missing source fails closed")
	records[7].spawn_key="tampered"
	check(not Policy.resolve_route(enemy,true,records).ok,"Tampered source binding fails closed")
	records[7].spawn_key="camp:7"
	check(Policy.resolve_route(enemy,false,{}).route=="standard","Existing non-map route remains standard")
	for count: int in [0,3,7,19,29,59,119]:
		for rarity: String in ["normal","magic","rare","boss"]:
			for test_profile: bool in [false,true]:
				for rewarded: bool in [false,true]:
					for demo: bool in [false,true]:
						enemy.rarity=rarity
						var p: Dictionary=Policy.plan("standard",enemy,rewarded,demo,count,test_profile)
						var eligible: bool=rewarded and not demo
						var n: int=count+(1 if eligible else 0)
						check(p.ok and p.eligible==eligible and p.reward_kills==n and p.charge_flasks==eligible,"Eligibility and next count")
						check(p.xp==(12 if eligible else 0) and p.normal_xp==(eligible and not test_profile),"XP amount/profile only for eligible rewards")
						check(p.equipment==(eligible and (n%8==0 or rarity in ["rare","boss"])) and p.jewel==(eligible and n%20==0),"Equipment and jewel boundaries")
						check(p.gem==(eligible and test_profile and n%30==0) and p.flask==(eligible and test_profile and n%60==0),"Test gem/flask boundaries")
						check(p.special_jewel==(eligible and rarity=="boss") and p.pickup==(eligible and n%4==0),"Boss and pickup boundaries")
						check(Policy.milestone_due(p,60)==(eligible and not test_profile) and not Policy.milestone_due(p,59),"Actual post-XP milestone count")
	enemy.rarity="normal"
	check(var_to_bytes([enemy,records])==before,"Policy never mutates input values")
	var hint := RarityHint.new()
	for flags: Array in [[false,false],[false,true],[true,true]]:
		var p: Dictionary=Policy.plan("standard",{"xp_reward":{},"rarity":hint},flags[0],flags[1],59,false)
		check(p.ok and not p.eligible and p.reward_kills==59 and p.xp==0,"Rewardless malformed XP is never read")
		check(hint.reads==0,"Rewardless rarity is never read or converted")
	print("KILL_REWARD_POLICY checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
