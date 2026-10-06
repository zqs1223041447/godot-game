extends SceneTree
const Attack = preload("res://scripts/combat/attack_hit_rules.gd")
func _initialize() -> void:
 var rows := {}
 for evasion: float in [320.0,1200.0,1600.0,2000.0,2400.0]:
  var values := {}
  for accuracy: float in [100.0,128.0,165.0,284.0,304.0,414.0,600.0]:
   values[str(accuracy)] = Attack.chance(accuracy,evasion)
  rows[str(evasion)] = values
 print(JSON.stringify(rows))
 quit(0)
