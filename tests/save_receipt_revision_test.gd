extends SceneTree
const Model=preload("res://scripts/canonical_game_state.gd")
const Icons=preload("res://scripts/visuals/skill_emblem.gd")
var retained_icons:Dictionary=Icons.ICONS
class FaultModel extends Model:
	var fail_writes:=false
	var mutate_during_write:=false
	func _write_bytes(path:String,bytes:PackedByteArray)->Error:
		if fail_writes:return ERR_CANT_CREATE
		if mutate_during_write:
			_current.progress.xp+=1;_current.revision+=1
		return super._write_bytes(path,bytes)
var checks:=0
var failures:=0
func _initialize()->void:
	var isolated:=OS.get_environment("XDG_DATA_HOME")
	if (not isolated.begins_with("/tmp/godot-m1-") and not isolated.begins_with("/workspace/scratch/a51485f153de/v023-profile-users/")) or not OS.get_user_data_dir().begins_with(isolated+"/"):quit(78);return
	var state:=FaultModel.new();var path:="user://receipt.json"
	check(not state.crafting_change_already_saved() and state._disk_revision==-1,"New model has no receipt")
	check(state.save_build(path)==OK and state.crafting_change_already_saved(),"Successful save produces an exact receipt")
	var saved:=state.snapshot();var disk:=FileAccess.get_file_as_bytes(path);var revision:int=state._disk_revision
	state.add_xp(1)
	check(state.revision()!=revision and not state.crafting_change_already_saved(),"Different revision can only reject saved equality")
	state.fail_writes=true
	check(state.save_build(path)!=OK and state._disk_revision==revision and state._disk_bytes==disk,"Failed save retains the previous byte/revision receipt")
	state.fail_writes=false;state._accept_memory(saved.duplicate(true))
	check(state.crafting_change_already_saved(),"Returning to the exact saved bytes is still recognized")
	state._current.progress.xp+=1
	check(state.revision()==revision and not state.crafting_change_already_saved(),"Same-revision in-place mutation reaches exact byte comparison")
	state._accept_memory(saved.duplicate(true));state._current.erase("revision")
	check(not state.crafting_change_already_saved(),"Missing revision is a safe negative receipt")
	state._accept_memory(saved.duplicate(true));state._current.revision=float(revision)
	check(not state.crafting_change_already_saved(),"Wrong revision type cannot create a receipt")
	state._accept_memory(saved.duplicate(true))
	var future_path:="user://future.json";FileAccess.open(future_path,FileAccess.WRITE).store_string('{"version":17}')
	check(not state.load_build(future_path) and state._disk_revision==revision and state._disk_bytes==disk and state.crafting_change_already_saved(),"Rejected future load preserves the existing receipt")
	var reopened:=FaultModel.new()
	check(reopened.load_build(path) and reopened._disk_revision==revision and reopened.crafting_change_already_saved(),"Validated load restores the exact saved revision")
	reopened.mutate_during_write=true
	check(reopened.save_build(path)==OK,"Writer callback fixture returns success")
	var written:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	check(reopened._disk_revision==int(written.revision) and reopened._disk_revision!=reopened.revision(),"Receipt revision is captured with serialized bytes before the writer callback")
	check(not reopened.crafting_change_already_saved(),"Callback mutation cannot masquerade as the saved bytes")
	reopened.mutate_during_write=false
	check(reopened.save_build(path)==OK and reopened.crafting_change_already_saved(),"Explicit later save establishes a new exact receipt")
	check(not reopened.load_build("user://missing-new-target.json") and reopened._disk_revision==-1 and not reopened.crafting_change_already_saved(),"Selecting a missing new target clears receipt applicability like existing disk state")
	print("Save receipt revision: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
