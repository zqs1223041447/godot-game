extends SceneTree
class ArenaProbe:
	extends Node
	var calls := 0
	var result: Dictionary = {"ok":false,"reason":"结算保存失败，请重试"}
	func request_safe_exit() -> Dictionary:
		calls += 1
		return result.duplicate(true)
class HudProbe:
	extends "res://scripts/game_hud.gd"
	var messages: Array[String] = []
	func notify(message: String) -> void:
		messages.append(message)
var checks := 0
var failures := 0
func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void:
	var arena := ArenaProbe.new()
	var hud := HudProbe.new()
	hud._arena = arena
	hud._exit_game()
	expect(arena.calls == 1, "HUD delegates to authoritative safe exit")
	expect(hud.messages == ["结算保存失败，请重试"], "Failure reason reaches player")
	hud._exit_game()
	expect(arena.calls == 2 and hud.messages.size() == 2, "Retry remains available after failure")
	arena.result = {"ok":true}
	hud._exit_game()
	expect(arena.calls == 3 and hud.messages.size() == 2, "Success delegates quit, without misleading failure")
	arena.result = {"ok":false}
	hud._exit_game()
	expect(hud.messages.back() == "保存失败，请重试", "Missing reason has concise fallback")
	var source := FileAccess.get_file_as_string("res://scripts/game_hud.gd")
	expect(not source.contains("退出（未保存）"), "No misleading unsafe-exit label")
	expect(source.count('_button("保存并退出", "ExitButton", _exit_game') == 2, "Pause and death buttons share safe route")
	hud.free()
	arena.free()
	print("Safe exit HUD: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
