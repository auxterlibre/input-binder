@tool

const LAYOUT_SETTING := "addons/input_binder/layout"


static func list_actions() -> PackedStringArray:
	var actions := PackedStringArray()
	for property in ProjectSettings.get_property_list():
		var setting_name: String = property.name
		if setting_name.begins_with("input/"):
			actions.append(setting_name.trim_prefix("input/"))
	return actions


static func has_action(action: String) -> bool:
	return ProjectSettings.has_setting("input/" + action)


static func is_builtin(action: String) -> bool:
	return action.begins_with("ui_")


static func get_action(action: String) -> Dictionary:
	var stored = ProjectSettings.get_setting("input/" + action)
	if not stored is Dictionary:
		return {"deadzone": 0.5, "events": []}
	var events := []
	for event in stored.get("events", []):
		if event is InputEvent:
			events.append(event.duplicate())
	return {"deadzone": float(stored.get("deadzone", 0.5)), "events": events}


static func set_action(action: String, deadzone: float, events: Array) -> void:
	ProjectSettings.set_setting("input/" + action, {"deadzone": deadzone, "events": events})


static func add_action(action: String) -> void:
	set_action(action, 0.5, [])


static func remove_action(action: String) -> void:
	if has_action(action):
		ProjectSettings.set_setting("input/" + action, null)


static func rename_action(old_name: String, new_name: String) -> void:
	var data := get_action(old_name)
	remove_action(old_name)
	set_action(new_name, data.deadzone, data.events)


static func action_name_error(action: String) -> String:
	if action.strip_edges().is_empty():
		return "Name cannot be empty."
	for banned in ["/", ":", "=", "\\", "\""]:
		if action.contains(banned):
			return "Name cannot contain '/', ':', '=', '\\' or '\"'."
	return ""


static func action_data_equal(a: Dictionary, b: Dictionary) -> bool:
	if not is_equal_approx(float(a.deadzone), float(b.deadzone)):
		return false
	var a_events: Array = a.events
	var b_events: Array = b.events
	if a_events.size() != b_events.size():
		return false
	for i in a_events.size():
		if var_to_str(a_events[i]) != var_to_str(b_events[i]):
			return false
	return true


static func is_builtin_customized(action: String) -> bool:
	if not is_builtin(action):
		return false
	var default = ProjectSettings.property_get_revert("input/" + action)
	if not default is Dictionary:
		return false
	var normalized := {"deadzone": float(default.get("deadzone", 0.5)), "events": default.get("events", [])}
	return not action_data_equal(get_action(action), normalized)


static func revert_builtin(action: String) -> void:
	if not is_builtin(action):
		return
	# set_setting(null) erases the builtin for the session; writing the default back reverts it.
	var default = ProjectSettings.property_get_revert("input/" + action)
	if default is Dictionary:
		ProjectSettings.set_setting("input/" + action, default)


static func get_layout() -> Dictionary:
	var stored = ProjectSettings.get_setting(LAYOUT_SETTING, {})
	if stored is Dictionary and stored.get("categories") is Array:
		return stored.duplicate(true)
	return {"categories": []}


static func set_layout(layout: Dictionary) -> void:
	var categories: Array = layout.get("categories", [])
	if categories.is_empty():
		if ProjectSettings.has_setting(LAYOUT_SETTING):
			ProjectSettings.set_setting(LAYOUT_SETTING, null)
	else:
		ProjectSettings.set_setting(LAYOUT_SETTING, layout)


static func category_names(layout: Dictionary) -> PackedStringArray:
	var names := PackedStringArray()
	for category in layout.categories:
		names.append(category.name)
	return names


static func find_category(layout: Dictionary, name: String) -> Dictionary:
	for category in layout.categories:
		if category.name == name:
			return category
	return {}


static func unique_category_name(layout: Dictionary, base: String) -> String:
	var names := category_names(layout)
	if not base in names:
		return base
	var n := 2
	while "%s %d" % [base, n] in names:
		n += 1
	return "%s %d" % [base, n]


static func add_category(layout: Dictionary, name: String) -> String:
	var unique := unique_category_name(layout, name)
	layout.categories.append({"name": unique, "actions": []})
	return unique


static func rename_category(layout: Dictionary, old_name: String, new_name: String) -> void:
	var category := find_category(layout, old_name)
	if not category.is_empty():
		category.name = new_name


static func remove_category(layout: Dictionary, name: String) -> void:
	for i in layout.categories.size():
		if layout.categories[i].name == name:
			layout.categories.remove_at(i)
			return


static func move_category(layout: Dictionary, name: String, to_index: int) -> void:
	for i in layout.categories.size():
		if layout.categories[i].name == name:
			var category = layout.categories[i]
			layout.categories.remove_at(i)
			layout.categories.insert(clampi(to_index, 0, layout.categories.size()), category)
			return


static func category_of(layout: Dictionary, action: String) -> String:
	for category in layout.categories:
		if action in category.actions:
			return category.name
	return ""


static func unassign(layout: Dictionary, action: String) -> void:
	for category in layout.categories:
		category.actions.erase(action)


static func assign(layout: Dictionary, action: String, category_name: String, index := -1) -> void:
	unassign(layout, action)
	var category := find_category(layout, category_name)
	if category.is_empty():
		return
	if index < 0 or index > category.actions.size():
		category.actions.append(action)
	else:
		category.actions.insert(index, action)


static func rename_in_layout(layout: Dictionary, old_name: String, new_name: String) -> void:
	for category in layout.categories:
		var i: int = category.actions.find(old_name)
		if i >= 0:
			category.actions[i] = new_name


static func split_prefix(action: String) -> String:
	var split_at := -1
	for separator in ["_", "."]:
		var i := action.find(separator)
		if i > 0 and (split_at < 0 or i < split_at):
			split_at = i
	return action.substr(0, split_at) if split_at > 0 else ""


static func propose_categories(layout: Dictionary, actions: PackedStringArray, regroup: bool) -> Dictionary:
	var proposal: Dictionary = {"categories": []} if regroup else layout.duplicate(true)
	var by_prefix := {}
	for action in actions:
		if is_builtin(action):
			continue
		if not regroup and not category_of(layout, action).is_empty():
			continue
		var prefix := split_prefix(action)
		if prefix.is_empty():
			continue
		if not by_prefix.has(prefix):
			by_prefix[prefix] = []
		by_prefix[prefix].append(action)
	for prefix in by_prefix:
		var target := ""
		for category in proposal.categories:
			if category.name.to_lower() == prefix.to_lower():
				target = category.name
				break
		if target.is_empty():
			if by_prefix[prefix].size() < 2:
				continue
			target = add_category(proposal, prefix.capitalize())
		for action in by_prefix[prefix]:
			assign(proposal, action, target)
	return proposal


static func snapshot() -> Dictionary:
	var actions := {}
	for action in list_actions():
		actions[action] = get_action(action)
	return {"actions": actions, "layout": get_layout()}


static func restore(snap: Dictionary) -> void:
	for action in list_actions():
		if not snap.actions.has(action):
			remove_action(action)
	for action in snap.actions:
		var data: Dictionary = snap.actions[action]
		# Default events compare by reference, so rewriting unchanged data serializes every ui_* action.
		if not action_data_equal(data, get_action(action)):
			set_action(action, data.deadzone, data.events)
	set_layout(snap.layout)


static func save() -> void:
	ProjectSettings.save()
