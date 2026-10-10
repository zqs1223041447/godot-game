extends RefCounted
## Test-only closure: verify the original manifest before redirecting preloads.
## Keep original frozen sources/expected hashes and the live production graph untouched.
const MANIFEST="res://docs/qa/v103-rules/frozen/manifest.json"
const DIR="user://v103-isolated-oracle/"
const TARGET="res://docs/qa/v103-rules/frozen/targeted_reforge_rules.gd"
const CRAFT="res://docs/qa/v103-rules/frozen/crafting_rules.gd"
const PATHS=["res://scripts/combat/damage_resolver.gd","res://scripts/mechanics/defense_rules.gd",
	"res://scripts/items/equipment_catalog.gd","res://scripts/items/crafting_expansion_rules.gd",TARGET,CRAFT]
static func source_text(path:String)->String:
	if path=="res://scripts/combat/damage_resolver.gd":
		return "class_name DamageResolver\n"+FileAccess.get_file_as_string("res://tests/fixtures/chaos_v92_frozen/damage_resolver.gd")
	if path=="res://scripts/mechanics/defense_rules.gd":
		return FileAccess.get_file_as_string("res://tests/fixtures/v103_dependency_isolation/defense_rules.txt")
	return FileAccess.get_file_as_string(path)
static func load_oracle()->Dictionary:
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	for entry:Dictionary in manifest.shared_unchanged_dependencies:
		if source_text("res://"+entry.path).sha256_text()!=entry.sha256:return {}
	for entry:Dictionary in manifest.frozen:
		if FileAccess.get_sha256("res://"+entry.path)!=entry.transformed_sha256:return {}
	if DirAccess.make_dir_recursive_absolute(DIR)!=OK:return {}
	var redirects:Dictionary={}
	for i:int in range(PATHS.size()):redirects[PATHS[i]]=DIR+str(i)+".gd"
	for path:String in PATHS:
		var code:=source_text(path)
		if code.begins_with("class_name "):code=code.substr(code.find("\n")+1)
		for original:String in redirects:code=code.replace('preload("'+original+'")','preload("'+redirects[original]+'")')
		var file:=FileAccess.open(redirects[path],FileAccess.WRITE)
		if file==null:return {}
		file.store_string(code);file.close()
	var targeted=load(redirects[TARGET]);var craft=load(redirects[CRAFT])
	if targeted==null or craft==null:return {}
	return {"targeted":targeted,"craft":craft}
