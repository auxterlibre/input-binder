@tool

const Store := preload("res://addons/input_binder/input_store.gd")
const ConstantsGen := preload("res://addons/input_binder/constants_gen.gd")

const ACTION_METHODS := "is_action_pressed|is_action_just_pressed|is_action_just_released|is_action_released|is_action|get_action_strength|get_action_raw_strength|get_axis|get_vector|action_press|action_release|has_action|erase_action|action_get_deadzone|action_set_deadzone"


static func extract_references(source: String) -> Array:
	var out := []
	var call_regex := RegEx.new()
	call_regex.compile("\\b(%s)\\s*\\(([^()]*)\\)" % ACTION_METHODS)
	var literal_regex := RegEx.new()
	literal_regex.compile("&?\"([^\"]+)\"")
	var lines := source.split("\n")
	for i in lines.size():
		for call in call_regex.search_all(lines[i]):
			var method := call.get_string(1)
			for literal in literal_regex.search_all(call.get_string(2)):
				out.append({"name": literal.get_string(1), "line": i + 1, "method": method})
	return out


static func collect_files(root: String, extensions: PackedStringArray, include_addons: bool) -> PackedStringArray:
	var out := PackedStringArray()
	_walk(root, extensions, include_addons, out)
	return out


static func _walk(dir_path: String, extensions: PackedStringArray, include_addons: bool, out: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		var path := dir_path.path_join(entry)
		if dir.current_is_dir():
			var skip := entry.begins_with(".") \
				or path == "res://addons/input_binder" \
				or (path == "res://addons" and not include_addons)
			if not skip:
				_walk(path, extensions, include_addons, out)
		elif entry.get_extension() in extensions and path != ConstantsGen.OUTPUT_PATH:
			out.append(path)
		entry = dir.get_next()
	dir.list_dir_end()


static func scan(root: String, include_addons: bool, defined: PackedStringArray) -> Dictionary:
	var script_paths := collect_files(root, PackedStringArray(["gd"]), include_addons)
	var scene_paths := collect_files(root, PackedStringArray(["tscn", "tres"]), include_addons)
	var used := {}
	var undefined := []
	for path in script_paths:
		var source := FileAccess.get_file_as_string(path)
		for reference in extract_references(source):
			if reference.name in defined:
				used[reference.name] = true
			else:
				reference["path"] = path
				undefined.append(reference)
		for action in defined:
			if not used.has(action) and source.contains("\"%s\"" % action):
				used[action] = true
	for path in scene_paths:
		var text := FileAccess.get_file_as_string(path)
		for action in defined:
			if not used.has(action) and text.contains("\"%s\"" % action):
				used[action] = true
	var unused := PackedStringArray()
	for action in defined:
		if not Store.is_builtin(action) and not used.has(action):
			unused.append(action)
	return {
		"unused": unused,
		"undefined": undefined,
		"scripts": script_paths.size(),
		"scenes": scene_paths.size(),
	}


static func find_uses(root: String, action: String, include_addons: bool) -> Array:
	var out := []
	var needle := "\"%s\"" % action
	for path in collect_files(root, PackedStringArray(["gd", "tscn", "tres"]), include_addons):
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			if lines[i].contains(needle):
				out.append({"path": path, "line": i + 1, "text": lines[i].strip_edges().left(120)})
	return out
