extends SceneTree
const Preview = preload("res://scripts/combat/damage_preview.gd")
const Character = preload("res://scripts/ui/canonical_character_panel.gd")
var checks := 0
var failures := 0
func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void:
	var profile := {"ok": true, "health": {"attack_fraction": 0.01, "physical_attack_fraction": 0.004, "instance_rate": 2.6, "total_rate_cap": 26.0}, "mana": {"attack_fraction": 0.0, "physical_attack_fraction": 0.003, "instance_rate": 2.8, "total_rate_cap": 28.0}}
	var cast := {"ok": true, "packets": {"direct": {}}, "leech": {"health": profile.health, "mana": profile.mana}}
	var before := var_to_bytes(cast)
	var lines := Preview.leech_lines(cast)
	expect(lines.size() == 2, "Two resources have separate concise lines")
	expect(lines[0] == "生命偷取：攻击 1.00% · 物理攻击 0.40%", "Physical and all-attack shares remain distinct")
	expect(lines[1] == "法力偷取：物理攻击 0.30%", "Zero components stay hidden")
	expect(var_to_bytes(cast) == before, "Preview is read-only")
	expect(Preview.leech_lines({"ok": true, "packets": {"direct": {}}}).is_empty(), "Legacy or ineligible casts have no invented leech")
	expect(Preview.leech_lines({"ok": false, "leech": cast.leech}).is_empty(), "Invalid casts stay hidden")
	expect(Preview.leech_lines({"ok": true, "packets": {}, "leech": cast.leech}).is_empty(), "Utility stays hidden")
	var values := Character.leech_stat_values(profile)
	expect(values.health_leech_instance == 2.6 and values.health_leech_cap == 26.0, "Health reads authoritative rates")
	expect(values.mana_leech_instance == 2.8 and values.mana_leech_cap == 28.0, "Mana reads independent authoritative rates")
	profile.health.attack_fraction = 0.0
	profile.health.physical_attack_fraction = 0.0
	values = Character.leech_stat_values(profile)
	expect(not values.has("health_leech_instance") and values.has("mana_leech_instance"), "Missing source does not imply passive recovery")
	expect(Character.leech_stat_values({"ok": false}).is_empty(), "Invalid state profile has no plausible numbers")
	print("Leech preview: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
