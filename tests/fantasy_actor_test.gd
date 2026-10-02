extends SceneTree
## Portable presentation contract test. Synthetic fixtures only; no game saves or RNG.
const Actors = preload("res://scripts/visuals/fantasy_actors.gd")
const Preferences = preload("res://scripts/visuals/visual_settings.gd")
const GameDataSource = preload("res://scripts/game_data.gd")
const EquipmentSource = preload("res://scripts/items/equipment_catalog.gd")
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
class Gear extends RefCounted:
	var equipped: Dictionary = {"weapon": "ember_wand", "armor": "vitality_armor"}
	func get_item_definition(id: String) -> Dictionary:
		if id == "generated_blade":
			return {"base_name": "岚纺刃", "name": "岚纺刃"}
		if id == "generated_focus":
			return EquipmentSource.definition({"id": "gear_000001", "base_id": "runewood_focus", "rarity": "normal", "item_level": 1, "affixes": []})
		if id == "generated_emberhide":
			return {"base_id":"emberhide_vest","base_name":"灰烬皮甲","slot":"armor"}
		return GameDataSource.ITEMS.get(id, {}).duplicate(true)
class ActorCell extends Node2D:
	const ARENA := Rect2(-300, -300, 600, 600)
	var player_pos := Vector2.ZERO
	var player_facing := Vector2.RIGHT
	var elapsed: float = 2.1
	var shield: float = 25.0
	var invulnerable: float = 0.0
	var hurt_flash: float = 0.0
	var alive: bool = true
	var _stats: Dictionary = {"max_shield": 50.0}
	var state := Gear.new()
	var enemy: Dictionary = {}
	var preferences := Preferences.new()
	var demo_mode: bool = false
	var _font: Font = load("res://assets/fonts/arena_sans.otf")
	var draw_count: int = 0
	func _draw() -> void:
		draw_count += 1
		if enemy.is_empty():
			Actors.draw_player(self, preferences)
		else:
			Actors.draw_enemy(self, enemy, preferences)

var cells: Array[ActorCell] = []
var checks: int = 0
var failures: int = 0
var snapshots: Array[Dictionary] = []
func _initialize() -> void:
	call_deferred("run")
func snapshot(cell: Node2D) -> Dictionary:
	return {"pos": cell.player_pos, "facing": cell.player_facing, "elapsed": cell.elapsed,
		"shield": cell.shield, "invulnerable": cell.invulnerable, "hurt": cell.hurt_flash, "alive": cell.alive,
		"stats": cell._stats.duplicate(true), "equipped": cell.state.equipped.duplicate(true), "enemy": cell.enemy.duplicate(true),
		"motion": cell.preferences.motion, "effects": cell.preferences.effects_level, "font": cell.preferences.font_scale}
func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", message)

func run() -> void:
	var focus_definition: Dictionary = Gear.new().get_item_definition("generated_focus")
	expect(not focus_definition.is_empty(), "Runewood fixture resolves through the real equipment catalog")
	expect(Actors._weapon_form("gear_000001", focus_definition) == "staff", "Runewood focus uses wooden staff art")
	expect(Actors._weapon_form("gear_000001", {"base_id": "runewood_focus", "base_name": "误导短刃"}) == "staff", "Stable focus base takes priority over display-name suffix")
	expect(Actors._weapon_form("gear_000001", {"base_name": "符木法器"}) == "staff", "Runewood base-name fallback also uses staff art")
	expect(Actors._weapon_form("prism_bow", {"name": "棱光长弓"}) == "bow", "Existing bow keeps bow art")
	expect(Actors._weapon_form("gear_000002", {"base_name": "岚纺刃"}) == "blade", "Existing generated blade keeps blade art")
	for weapon: String in ["ember_wand", "swift_blade", "prism_bow", "generated_blade", "generated_focus", ""]:
		for direction: int in range(8):
			for preset: int in range(3):
				var cell := ActorCell.new()
				cell.player_facing = Vector2.RIGHT.rotated(direction * TAU / 8.0)
				cell.state.equipped.weapon = weapon
				if direction==2: cell.state.equipped.armor="generated_emberhide"
				cell.alive = direction != 7
				cell.hurt_flash = 0.1 if direction == 6 else 0.0
				cell.invulnerable = 0.8 if direction == 5 else 0.0
				cell.shield = [0.0, 25.0, 50.0][preset]
				cell.preferences.effects_level = preset
				cell.preferences.motion = preset != 0
				cell.preferences.font_scale = [1.0, 1.1, 1.2][preset]
				cell.elapsed = direction + 0.375
				cells.append(cell)
				root.add_child(cell)
	for template_id: String in ["crawler", "skitter", "brute", "rift_warden", "ember_guard"]:
		for rarity: String in ["normal", "magic", "rare", "boss"]:
			if (template_id == "rift_warden") != (rarity == "boss"):
				continue
			if template_id=="ember_guard" and rarity!="rare": continue
			for preset: int in range(3):
				var cell := ActorCell.new()
				cell.player_pos = Vector2(200, 0)
				cell.enemy = Monsters.make_enemy(cells.size() + 1, template_id, 1, Vector2.ZERO, "map_boss" if rarity == "boss" else "demo", rarity, [])
				cell.enemy.health = float(cell.enemy.max_health) * 0.25
				cell.enemy.max_shield = 50.0
				cell.enemy.shield = [0.0, 25.0, 50.0][preset]
				cell.enemy.slow = 1.0
				cell.enemy.flash = 0.1 if preset == 2 else 0.0
				cell.preferences.effects_level = preset
				cell.preferences.motion = preset != 0
				cell.preferences.font_scale = [1.0, 1.1, 1.2][preset]
				cell.demo_mode = true
				cells.append(cell)
				root.add_child(cell)
	for cell: Node2D in cells:
		snapshots.append(snapshot(cell))
	for frame: int in range(4):
		for cell: Node2D in cells:
			cell.queue_redraw()
		await process_frame
	var callbacks: int = 0
	for i: int in range(cells.size()):
		expect(snapshot(cells[i]) == snapshots[i], "Actor render mutated fixture %d" % i)
		expect(cells[i].draw_count > 0, "Fixture %d did not draw" % i)
		callbacks += cells[i].draw_count
	print("fantasy_actor_test: %d checks, %d failures; " % [checks, failures], cells.size(), " fixtures, ", callbacks,
		" draw callbacks; six weapon cases including catalog-resolved runewood focus, eight directions, three effect levels, motion on/off, alive/dead/hurt/invulnerable, species/rarity/health/shield/slow.")
	for cell: ActorCell in cells:
		cell.queue_free()
	await process_frame
	quit(1 if failures else 0)
