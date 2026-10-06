extends SceneTree
const Monsters=preload("res://scripts/monsters/monster_catalog.gd")
const Hits=preload("res://scripts/combat/attack_hit_rules.gd")
const Defense=preload("res://scripts/mechanics/defense_rules.gd")
const Maps=preload("res://scripts/world/normal_map_catalog.gd")
const Encounters=preload("res://scripts/encounters/encounter_compiler.gd")
const SourceData=preload("res://scripts/passives/source_tree_data.gd")
const ARMOUR=[30,50,55,80,85,120]
const EVASION=[200,260,270,350,360,450]
func _initialize()->void:call_deferred("run")
func run()->void:
	var rows:Array=[];var serial:=1
	for map_id:String in Maps.WAVES:
		for tier:int in range(1,4):
			var wave:int=Maps.definition(map_id,tier).wave
			for species:String in Monsters.TEMPLATES:
				if species=="brute" and wave<2:continue
				if species in ["ember_guard","brood_host"] and wave<3:continue
				if species=="frost_guard" and wave<4:continue
				if species=="storm_skitter" and wave<5:continue
				var rarities:Array=["boss"] if species=="rift_warden" else ["normal","magic","rare"] if species in ["crawler","skitter","brute","frost_guard","storm_skitter"] else [Monsters.TEMPLATES[species].rarity]
				for rarity:String in rarities:
					for damage_modifier:bool in [false,true]:
						var mechanisms:Array=Monsters.TEMPLATES[species].mechanisms.duplicate() if species not in ["crawler","skitter","brute","frost_guard","storm_skitter"] else [] if rarity=="normal" else ["ember_power"]
						var enemy:Dictionary=Monsters.make_enemy(serial,species,wave,Vector2.ZERO,"map_boss" if rarity=="boss" else "ordinary",rarity,mechanisms);serial+=1
						assert(not enemy.is_empty())
						var applied:Dictionary=Encounters.apply_to_enemy(enemy,Encounters.compile(["enemy_damage_115"] if damage_modifier else []).profile);assert(applied.ok);enemy=applied.enemy
						for stat:String in Hits.monster_profile(int(enemy.kind)):enemy[stat]=Hits.monster_profile(int(enemy.kind))[stat]
						if rarity=="boss":enemy.map_boss_attack_id=Maps.Maps.MAPS[map_id].boss_attack_id
						var components:Dictionary=Monsters.contact_components(enemy)
						var policy:Dictionary=Monsters.telegraph_policy(enemy)
						if not policy.is_empty():
							for type:String in components:components[type]*=float(policy.profile.damage_multiplier)
							if policy.has("burn_policy"):components.fire*=float(policy.burn_policy.upfront_fire_multiplier)
						var baseline:Dictionary=Defense.incoming_source_hit(components,{"armour":0.0},0.0,100000.0);assert(baseline.ok)
						var defended:Array=[]
						for rating:int in ARMOUR:
							var result:Dictionary=Defense.incoming_source_hit(components,{"armour":float(rating)},0.0,100000.0);assert(result.ok)
							defended.append({"armour":rating,"damage":result.damage_total})
						rows.append({"map":map_id,"tier":tier,"wave":wave,"species":species,"rarity":rarity,"mechanisms":mechanisms,"damage_modifier":damage_modifier,"accuracy":enemy.accuracy,"damage_base":enemy.damage,"delivery":"telegraph_attack" if not policy.is_empty() else "contact_attack","components":components,"before_armour":baseline.damage_total,"armour_rows":defended})
	var evasion_rows:Array=[]
	for class_id:int in range(7):
		var dex:float=float(SourceData.class_definition(class_id).base_dex)
		for rating:int in EVASION:
			var effective:float=(15.0+rating)*(1.0+floorf(dex/5.0)*0.01)
			evasion_rows.append({"class_id":class_id,"base_dexterity":dex,"flat_item_evasion":rating,"effective_evasion":effective,"enemy_accuracy":100.0,"hit_chance":Hits.chance(100.0,effective)})
	var report:Dictionary={"scope":"Deterministic existing catalog attack envelope for3maps9tiers, rarity and +15%damage; legal template wave gates, not a random encounter frequency or video/FPS test","armour_tier_endpoints":ARMOUR,"evasion_tier_endpoints":EVASION,"armour_rows":rows,"evasion_rows":evasion_rows,"all_actual_natural_accuracy_values":[100.0],"accuracy_source":"main._apply_source_actor_profile -> AttackHitRules.monster_profile; wave/rarity/map modifiers do not modify accuracy","zero_dex_t1_minimum_hit_chance":Hits.chance(100.0,215.0),"limitations":["No evasion can avoid non-attack damage or ongoingburn","Armour reduces onlyphysical hit components, notelemental/chaos/burn","Damage rows have no character resistances/shield/mana partition; isolate one stat budget","Map bosses use actual per-pulse multiplier; sunwell secondpulse is a separatehit","The two new affixes are globalflat ratings, not local item-defense multipliers"]}
	var f:=FileAccess.open("res://docs/qa/v062-budget/budget.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t",true,true));f.close()
	print("Defense budget: %d actual catalog attack rows, %d class/rating rows"%[rows.size(),evasion_rows.size()]);quit(0)
