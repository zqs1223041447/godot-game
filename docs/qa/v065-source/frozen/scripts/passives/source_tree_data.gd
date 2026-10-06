extends RefCounted
## Source identity, topology and original numbers. No imported official artwork,
## stat recalibration or claim that every source mechanism has an executor.
const PATH := "res://data/passives/official_tree_runtime.json"
const SOURCE_SHA256 := "7e9f755e33152129ebf36c2ebdad639c527e4ad70d274b1fefb860f30ca01122"
static var _data: Dictionary = {}
static var _nodes: Dictionary = {}


static func ready() -> bool:
	if not _data.is_empty(): return true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not parsed is Dictionary or parsed.get("schema_version") != 1 or not parsed.get("nodes") is Dictionary or parsed.nodes.size() != 3390 \
			or not parsed.get("source") is Dictionary or parsed.source.get("data_sha256") != SOURCE_SHA256 or parsed.source.get("version") != "3.29.1":
		return false
	_data = parsed
	for id: String in _data.nodes:
		var source: Dictionary = _data.nodes[id]
		var type := "small"
		if source.get("isMastery",false): type = "mastery"
		elif source.get("isKeystone",false): type = "keystone"
		elif source.get("isNotable",false): type = "notable"
		elif source.get("isJewelSocket",false): type = "socket"
		elif source.has("classStartIndex") or source.get("isAscendancyStart",false): type = "start"
		var position: Dictionary = _data.positions.get(id,{})
		_nodes[id] = {"id":id,"name":str(source.get("name","")),"type":type,
			"stats":source.get("stats",[]).duplicate(true),"mastery_effects":source.get("masteryEffects",[]).duplicate(true),
			"group_id":str(position.get("group_id","")),"has_position":not position.is_empty(),
			"position":Vector2(float(position.get("x",0)),float(position.get("y",0))),"source":source.duplicate(true)}
	return true


static func node(id: String) -> Dictionary:
	return _nodes.get(id,{}).duplicate(true) if ready() else {}
static func nodes() -> Dictionary:
	return _nodes.duplicate(true) if ready() else {}
static func standard_ids() -> Array:
	return _data.standard_tree.default_allocation_graph.node_ids.duplicate() if ready() else []
static func adjacency(id: String) -> Array:
	return _data.standard_tree.default_allocation_graph.adjacency.get(id,[]).duplicate() if ready() else []
static func class_starts() -> Array:
	return _data.standard_tree.class_start_nodes.duplicate(true) if ready() else []
static func start_for_class(class_id: int) -> String:
	for start: Dictionary in class_starts():
		if int(start.class_index) == class_id: return str(start.node_id)
	return ""
static func standard_socket_ids() -> Array:
	return _data.standard_tree.jewel_slot_ids.duplicate() if ready() else []
static func source_coverage() -> Dictionary:
	return _data.coverage.duplicate(true) if ready() else {}
static func groups() -> Dictionary:
	return _data.groups.duplicate(true) if ready() else {}
static func special_subtrees() -> Dictionary:
	return _data.special_subtrees.duplicate(true) if ready() else {}
static func source_points() -> Dictionary:
	return _data.points.duplicate(true) if ready() else {}
static func class_definition(class_id: int) -> Dictionary:
	return _data.classes[class_id].duplicate(true) if ready() and class_id >= 0 and class_id < _data.classes.size() else {}
static func edges_for(ids: Array) -> Array:
	if not ready(): return []
	var wanted := {}
	for id: String in ids: wanted[id]=true
	var result: Array = []
	for edge: Dictionary in _data.edges:
		if wanted.has(edge.id): result.append({"a":edge.a,"b":edge.b})
	return result
