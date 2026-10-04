extends SceneTree
const Monsters=preload("res://scripts/monsters/monster_catalog.gd")
const Markers=preload("res://scripts/visuals/world_markers.gd")
func _initialize() -> void:
	var checks: Array[bool] = []
	checks.append(Monsters.resistance_text({}).is_empty())
	checks.append(Monsters.resistance_text({"resistances":{"fire":0.25}})=="火抗 25%")
	var enemy := {"name":"守卫","rarity":"normal","resistances":{"fire":0.45,"cold":0.20,"lightning":0.20},"defense_stats":{"fire_resistance":1.2},"map_defense_source":{"resistance_bonus":0.20}}
	checks.append(Monsters.resistance_text(enemy,true)=="火抗45% · 冰抗20% · 电抗20%")
	checks.append(Monsters.mechanism_text(enemy).contains("火抗 45% · 冰抗 20% · 电抗 20%"))
	checks.append(Markers.caption(enemy).ends_with("火抗45% · 冰抗20% · 电抗20%"))
	enemy.resistances={"fire":0.75,"cold":0.75,"lightning":0.75}
	checks.append(not Monsters.resistance_text(enemy).contains("120%"))
	checks.append(Monsters.resistance_text(enemy).count("75%")==3)
	enemy.resistances={"fire":0.0,"cold":0.0,"lightning":0.0}
	checks.append(Monsters.resistance_text(enemy).is_empty())
	var failures: int=checks.count(false)
	print("Map resistance presentation: %d checks, %d failures" % [checks.size(),failures])
	quit(0 if failures==0 else 1)
