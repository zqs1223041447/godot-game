extends Control
## Minimal boot scene. Gameplay will be developed in later, focused changes.


func _ready() -> void:
	$Margin/Center/Content/QuitButton.grab_focus()
	print("godot-game: main scene ready")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_quit_pressed()


func _on_quit_pressed() -> void:
	get_tree().quit()
