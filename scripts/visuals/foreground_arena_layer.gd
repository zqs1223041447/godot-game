class_name ForegroundArenaLayer
extends Node2D
## Explicit final world stage, after all retained actor pieces and before HUD.
## Read-through properties use the authoritative arena; drawing targets this item.
const Visuals=preload("res://scripts/visuals/arena_visuals.gd")
var source:Node2D
var measured_frame:=-1
var measured_usec:=0
func _get(property:StringName)->Variant:
	return source.get(property) if is_instance_valid(source) else null
func visual_camera_zoom()->float:
	var camera:Camera2D=source.get_node_or_null("WorldCamera") as Camera2D
	return camera.zoom.x if camera!=null else 1.0
func burn_statuses() -> Array:
	return source.burn_statuses() if is_instance_valid(source) and source.has_method("burn_statuses") else []
func shock_statuses() -> Array:
	return source.shock_statuses() if is_instance_valid(source) and source.has_method("shock_statuses") else []
func trap_statuses() -> Array:
	return source.trap_statuses() if is_instance_valid(source) and source.has_method("trap_statuses") else []
func damage_feedback() -> Array:
	return source.damage_feedback() if is_instance_valid(source) and source.has_method("damage_feedback") else []
func _draw()->void:
	if not is_instance_valid(source) or not source._ready_complete:return
	var began:int=Time.get_ticks_usec() if Visuals.diagnostic_profile_enabled else 0
	Visuals.draw_after_actors(self,source.visual_settings)
	if Visuals.diagnostic_profile_enabled:measured_frame=Engine.get_process_frames();measured_usec=Time.get_ticks_usec()-began
