@tool

const Store := preload("res://addons/input_binder/input_store.gd")

const SECTION := "input_binder_preset"
const FORMAT_VERSION := 1


static func build_preset() -> Dictionary:
	var actions := {}
	for action in Store.list_actions():
		if not Store.is_builtin(action):
			actions[action] = Store.get_action(action)
	var layout := Store.get_layout()
	for category in layout.categories:
		var kept := []
		for action in category.actions:
			if actions.has(action):
				kept.append(action)
		category.actions = kept
	return {"version": FORMAT_VERSION, "actions": actions, "layout": layout}


static func save_preset(path: String) -> Error:
	var data := build_preset()
	var config := ConfigFile.new()
	config.set_value(SECTION, "version", data.version)
	config.set_value(SECTION, "layout", data.layout)
	for action in data.actions:
		config.set_value("actions", action, data.actions[action])
	return config.save(path)


static func load_preset(path: String) -> Dictionary:
	var config := ConfigFile.new()
	if config.load(path) != OK or not config.has_section(SECTION):
		return {}
	var actions := {}
	if config.has_section("actions"):
		for action in config.get_section_keys("actions"):
			if Store.is_builtin(action) or not Store.action_name_error(action).is_empty():
				continue
			var stored = config.get_value("actions", action)
			if not stored is Dictionary:
				continue
			var events := []
			for event in stored.get("events", []):
				if event is InputEvent:
					events.append(event)
			actions[action] = {"deadzone": float(stored.get("deadzone", 0.5)), "events": events}
	var layout = config.get_value(SECTION, "layout", {"categories": []})
	if not (layout is Dictionary and layout.get("categories") is Array):
		layout = {"categories": []}
	return {"version": int(config.get_value(SECTION, "version", 1)), "actions": actions, "layout": layout}


static func apply_preset(data: Dictionary, overwrite: bool) -> void:
	for action in data.actions:
		if Store.has_action(action) and not overwrite:
			continue
		var entry: Dictionary = data.actions[action]
		Store.set_action(action, entry.deadzone, entry.events)
	var layout := Store.get_layout()
	for preset_category in data.layout.categories:
		var name: String = preset_category.name
		if Store.find_category(layout, name).is_empty():
			name = Store.add_category(layout, name)
		for action in preset_category.actions:
			if Store.has_action(action):
				Store.assign(layout, action, name)
	Store.set_layout(layout)
