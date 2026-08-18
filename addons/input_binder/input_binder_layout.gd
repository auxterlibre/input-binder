@tool
class_name InputBinderLayout

const Store := preload("res://addons/input_binder/input_store.gd")


static func categories() -> PackedStringArray:
	return Store.category_names(Store.get_layout())


static func actions_in(category_name: String, include_builtins := false) -> PackedStringArray:
	var layout := Store.get_layout()
	var existing := Store.list_actions()
	var members: Array = []
	if category_name.is_empty():
		for action in existing:
			if Store.category_of(layout, action).is_empty():
				members.append(action)
	else:
		var category := Store.find_category(layout, category_name)
		if category.is_empty():
			return PackedStringArray()
		members = category.actions
	var out := PackedStringArray()
	for action in members:
		if not action in existing:
			continue
		if not include_builtins and Store.is_builtin(action):
			continue
		out.append(action)
	return out


static func category_of(action: String) -> String:
	return Store.category_of(Store.get_layout(), action)


static func display_name(action: String) -> String:
	return action.capitalize()


static func grouped(include_builtins := false) -> Dictionary:
	var out := {}
	for category_name in categories():
		out[category_name] = actions_in(category_name, include_builtins)
	var uncategorized := actions_in("", include_builtins)
	if not uncategorized.is_empty():
		out[""] = uncategorized
	return out
