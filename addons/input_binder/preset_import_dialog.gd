@tool
extends ConfirmationDialog

signal preset_confirmed(data: Dictionary, overwrite: bool)

const Store := preload("res://addons/input_binder/input_store.gd")

var _data: Dictionary
var _summary: Label
var _overwrite: CheckBox
var _preview: Tree


func _init() -> void:
	title = "Import Input Preset"
	var scale := EditorInterface.get_editor_scale()
	min_size = Vector2i(roundi(460.0 * scale), roundi(420.0 * scale))
	get_ok_button().text = "Import"

	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", roundi(6.0 * scale))
	add_child(box)

	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_summary)

	_overwrite = CheckBox.new()
	_overwrite.text = "Overwrite actions that already exist"
	_overwrite.toggled.connect(func(_pressed): _refresh())
	box.add_child(_overwrite)

	_preview = Tree.new()
	_preview.hide_root = true
	_preview.columns = 1
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_preview)

	confirmed.connect(func(): preset_confirmed.emit(_data, _overwrite.button_pressed))


func open_with(data: Dictionary) -> void:
	_data = data
	_overwrite.set_pressed_no_signal(false)
	_refresh()
	popup_centered()


func _refresh() -> void:
	_preview.clear()
	var root := _preview.create_item()
	var bg := get_theme_color(&"prop_subsection", &"Editor")
	var dim := get_theme_color(&"disabled_font_color", &"Editor")
	var warning := get_theme_color(&"warning_color", &"Editor")
	var listed := {}
	var new_count := 0
	for category in _data.layout.categories:
		var members := []
		for action in category.actions:
			if _data.actions.has(action):
				members.append(action)
		if members.is_empty():
			continue
		var category_item := root.create_child()
		category_item.set_text(0, category.name)
		category_item.set_icon(0, get_theme_icon(&"Folder", &"EditorIcons"))
		category_item.set_custom_bg_color(0, bg)
		for action in members:
			listed[action] = true
			if _add_row(category_item, action, dim, warning):
				new_count += 1
	var unlisted := []
	for action in _data.actions:
		if not listed.has(action):
			unlisted.append(action)
	if not unlisted.is_empty():
		var rest := root.create_child()
		rest.set_text(0, "No category")
		rest.set_icon(0, get_theme_icon(&"Folder", &"EditorIcons"))
		rest.set_custom_bg_color(0, bg)
		for action in unlisted:
			if _add_row(rest, action, dim, warning):
				new_count += 1
	var total: int = _data.actions.size()
	var existing := total - new_count
	var existing_fate := "will be overwritten" if _overwrite.button_pressed else "kept as-is"
	_summary.text = "%d actions in preset: %d new, %d existing (%s)." % [
		total, new_count, existing, existing_fate]
	get_ok_button().disabled = total == 0


func _add_row(parent: TreeItem, action: String, dim: Color, warning: Color) -> bool:
	var item := parent.create_child()
	var exists := Store.has_action(action)
	if not exists:
		item.set_text(0, action + "  (new)")
	elif _overwrite.button_pressed:
		item.set_text(0, action + "  (will overwrite)")
		item.set_custom_color(0, warning)
	else:
		item.set_text(0, action + "  (exists, kept)")
		item.set_custom_color(0, dim)
	return not exists
