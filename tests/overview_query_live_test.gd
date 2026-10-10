extends "res://tests/overview_live_short_test.gd"
## Reuse the original bounded dense/live flow; add current player marker checks.
## Per-frame measurements here are functional-probe records, not A/B evidence.
func sample_window(label:String,opened:bool)->void:
	await super.sample_window(label,opened)
	if opened:
		check(overview.player_position==arena.player_pos and overview.player_facing==arena.player_facing,label+": live overview has current player marker and facing")
		var before:Vector2=arena.player_pos
		Input.action_press("move_right")
		for frame:int in range(2):await process_frame
		Input.action_release("move_right");await process_frame
		check(arena.player_pos!=before and overview.player_position==arena.player_pos,label+": actual held movement updates marker without a cache delay")
