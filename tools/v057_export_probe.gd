extends SceneTree
const Game = preload("res://scripts/canonical_game_state.gd")
const Data = preload("res://scripts/passives/source_tree_data.gd")
const Runtime = preload("res://scripts/passives/source_tree_runtime.gd")
const Localization = preload("res://scripts/passives/source_tree_localization.gd")
const Sheet = preload("res://scripts/ui/canonical_passive_panel.gd")
var rows: Array[Dictionary] = []
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	rows.append({"ok":ok,"label":label})
	if not ok: failures+=1;push_error(label)
func sha(bytes: PackedByteArray) -> String:
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(bytes);return h.finish().hex_encode()
func run() -> void:
	var output:=OS.get_environment("V057_PACK_QA");var pack:=OS.get_environment("V057_MAIN_PACK");var fixture:=OS.get_environment("V057_OLD_SAVE")
	if output.is_empty() or pack.is_empty() or fixture.is_empty() or not ProjectSettings.globalize_path("res://").is_empty() or not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v057-"):quit(78);return
	create_timer(30.0).timeout.connect(func():push_error("Packed localization probe did not finish");quit(1))
	DirAccess.make_dir_recursive_absolute(output)
	var original:=FileAccess.get_file_as_bytes(fixture);var file:=FileAccess.open("user://build_save.json",FileAccess.WRITE);file.store_buffer(original);file.close()
	var model:=Game.new();var loaded:=model.load_build("user://build_save.json")
	check(loaded and model.snapshot().version==34,"Actual old schema34 ownership loads without migration")
	check(str(ProjectSettings.get_setting("application/config/version"))=="0.57.0","Actual packed version")
	check(str(ProjectSettings.get_setting("application/config/custom_user_dir_name"))=="godot-game-preview-v021" and model.bag_layout()=={"pages":2,"columns":12,"rows":10},"Original save directory and240slots")
	check(Data.ready() and Localization.ready() and Runtime.CURRENT_SAVE_VERSION==33,"Packed mapping loads with current execution vocabulary33")
	check(sha(FileAccess.get_file_as_bytes(Localization.PATH))==OS.get_environment("V057_MAPPING_SHA256"),"Packed localization JSON is exact frozen content")
	check(sha(FileAccess.get_file_as_bytes(Data.PATH))==OS.get_environment("V057_SOURCE_TREE_SHA256"),"Authoritative English runtime tree is unchanged")
	check(not FileAccess.file_exists("res://data/passive_source/data.json") and not FileAccess.file_exists("res://data/passive_source/normalized_tree.json") and not FileAccess.file_exists("res://data/passive_source/source_manifest.json"),"Research source files stay outside the pack")
	var font:=load("res://assets/fonts/arena_sans.otf") as FontFile;font.allow_system_fallback=false
	check(sha(font.data)==OS.get_environment("V057_PACK_FONT_SHA256"),"Actual packed font matches the frozen expanded subset")
	var doc:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(Localization.PATH));var strings:Array=[]
	for row:Dictionary in doc.nodes.values():strings.append(str(row.zh_CN))
	strings.append_array(doc.lines.values());strings.append_array(doc.classes.values())
	for row:Dictionary in doc.partitions.values():strings.append(str(row.zh_CN))
	strings.append(Localization.TERM_NOTE+Localization.NOT_IMPLEMENTED)
	var missing:Dictionary={};var han:Dictionary={}
	for value:String in strings:
		for i:int in range(value.length()):
			var cp:=value.unicode_at(i)
			if (cp>=0x3400 and cp<=0x9fff) or (cp>=0xf900 and cp<=0xfaff):
				han[cp]=true
				if not font.has_char(cp):missing[cp]=true
	check(missing.is_empty() and han.size()>1200,"All unique mapped Chinese glyphs exist without system fallback")
	check(doc.nodes.size()==3390 and doc.lines.size()==2974,"Complete source IDs and exact effect-map keys load from PCK")
	check(Localization.source_effect_line("10% more Damage if you've Killed Recently").contains("额外提高") and Localization.source_effect_line("10% reduced Attack Speed").contains("降低"),"Independent MORE and additive reduced terms remain distinct")
	check(Localization.display_line("+12% to Fire Damage over Time Multiplier").contains("+12%") and not Localization.display_line("+12% to Fire Damage over Time Multiplier").contains(Localization.NOT_IMPLEMENTED),"Implemented Fire DoT multiplier has no unsupported label")
	check(Localization.line_status("Damaging Ailments deal damage 5% faster").implemented and not Localization.display_line("Damaging Ailments deal damage 5% faster").contains(Localization.NOT_IMPLEMENTED),"Current faster-burn consumer is reflected dynamically")
	var mixed:Array=Runtime.lines_for("48823")
	check(Runtime.node_effect("48823").status=="partial" and Localization.display_lines(mixed).count(Localization.NOT_IMPLEMENTED)==1,"Mixed Bow DoT and faster node remains partial with one marker")
	var mastery:Array=Runtime.lines_for("11505",36313)
	check(Runtime.node_effect("11505",36313).status=="partial" and Localization.display_lines(mastery).count(Localization.NOT_IMPLEMENTED)==1,"Mixed Fire DoT mastery labels its unsupported duration row only")
	var before:=var_to_bytes(model.snapshot());var stats:=var_to_bytes(model.get_stats());seed(570057);var expected:=randf();seed(570057)
	var panel:=Sheet.new();root.add_child(panel);panel.setup(model,"user://build_save.json");await process_frame
	check(panel._class.item_count==7 and panel._partition.item_count==39 and panel._tree._nodes.size()==2387,"Actual packed panel opens translated standard tree and all pickers")
	panel._find_node("wind dancer");var selected:String=panel.selected_node_id;panel._find_node(Localization.node_name(selected))
	check(selected=="11239" and panel.selected_node_id==selected and panel._detail.text.contains(Localization.NOT_IMPLEMENTED),"Chinese and original English names share actual search identity")
	panel._find_node("11239")
	check(panel.selected_node_id==selected,"Original ID search remains available")
	panel._change_partition(1);var branch:Dictionary=Data.special_subtrees().ascendancies.get(panel._subtree,{})
	check(not branch.is_empty() and panel._tree._nodes.size()==branch.positioned_node_ids.size() and panel._tree._nodes.size()!=2387,"Clean cached panel genuinely switches to an ascendancy partition")
	panel._focus_start()
	check(panel._tree._nodes.size()==2387 and panel.selected_node_id==Data.start_for_class(int(model.snapshot().talents.class_id)),"Return to current class rebuilds the standard graph")
	check(randf()==expected and var_to_bytes(model.snapshot())==before and var_to_bytes(model.get_stats())==stats,"Display/search/partition reads leave model stats and RNG unchanged")
	check(FileAccess.get_file_as_bytes("user://build_save.json")==original and not FileAccess.file_exists("user://build_save.json.v34-backup.json"),"Display-only batch preserves original save bytes and creates no migration backup")
	var report:Dictionary={"ok":failures==0 and rows.size()==22,"checks":rows.size(),"failures":failures,"results":rows,"source_commit":OS.get_environment("V057_SOURCE"),"pck_sha256":sha(FileAccess.get_file_as_bytes(pack)),"mapping_sha256":sha(FileAccess.get_file_as_bytes(Localization.PATH)),"font_sha256":sha(font.data),"mapped_chinese_glyphs":han.size(),"schema":34,"execution_vocabulary":33,"scope":"Linux same-PCK display/data read verification; no Windows hardware or physical pointer claim"}
	FileAccess.open(output.path_join("packed-runtime-probe.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true));print("Packed v57 localization probe: %d checks, %d failures"%[rows.size(),failures]);panel.queue_free();await process_frame;quit(0 if report.ok else 1)
