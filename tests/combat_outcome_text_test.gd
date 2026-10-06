extends SceneTree
const Art = preload("res://scripts/visuals/combat_feedback_renderer.gd")
const Hud = preload("res://scripts/game_hud.gd")
var checks := 0
var failures := 0
func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void:
	var row := {"kind":"evaded","target_kind":"monster","count":1,"age":0.0,"lifetime":0.75}
	var before := var_to_bytes(row)
	expect(Art.presentation(row).text == "闪避", "True miss has no fabricated damage amount")
	row.count = 3
	expect(Art.presentation(row).text == "闪避 ×3", "Combined miss count")
	row.age = 0.75
	expect(Art.presentation(row).is_empty(), "Expired observer hidden")
	row.age = 0.0
	row.target_kind = "player"
	expect(Art.presentation(row).is_empty(), "No invented player miss scope")
	expect(Art.presentation({"kind":"hit","amount":0.0}).is_empty(), "Legacy zero damage presentation unchanged")
	expect(Art.presentation({"kind":"hit","amount":0.0001}).text == "<0.01", "Small positive loss not zero")
	expect(Hud.observed_damage_text(0.0) == "0.00" and Hud.observed_damage_text(0.000001) == "<0.01", "F6 distinguishes exact zero")
	var outcome := {"outcome":"evaded","target_id":4,"cast_id":12,"projectile_id":5,"chance":0.77,"at":3.0}
	var original := var_to_bytes(outcome)
	var text := Hud.combat_outcome_text(outcome)
	expect(text.contains("被闪避") and text.contains("77.0%") and text.contains("敌人 #4"), "Known outcome and admission probability")
	expect(var_to_bytes(outcome) == original, "F6 read only")
	text = Hud.combat_outcome_text({"outcome":"terrain_blocked","target_id":0,"cast_id":0})
	expect(text.contains("撞墙") and text.contains("目标未知") and text.contains("编号未知"), "Missing identity not invented")
	expect(not text.contains("命中率"), "Terrain gets no probability")
	expect(Hud.combat_outcome_text({"outcome":"spawn_protected"}).contains("进入结算后"), "Protection observation boundary explicit")
	expect(Hud.combat_outcome_text({"outcome":"zero_damage"}).contains("实际损失为零"), "Actual zero identified")
	print("Combat outcome text: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
