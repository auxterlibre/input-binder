@tool
extends ConfirmationDialog

signal layout_confirmed(layout: Dictionary)

const Store := preload("res://addons/input_binder/input_store.gd")

var _current: Dictionary
var _actions: PackedStringArray
var _proposed: Dictionary
var _summary: Label
var _regroup: CheckBox
var _preview: Tree


func _init() -> void:
	title = "Auto-Categorize by Prefix"
	var scale := EditorInterface.get_editor_scale()
	min_size = Vector2i(roundi(460.0 * scale), roundi(420.0 * scale))
	get_ok_button().text = "Apply"

	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", roundi(6.0 * scale))
	add_child(box)

	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_summary)

	_regroup = CheckBox.new()
	_regroup.text = "Re-group actions that are already categorized"
	_regroup.tooltip_text = "Rebuild every category from the name prefixes, instead of only sorting uncategorized actions."
	_regroup.toggled.connect(func(_pressed): _refresh())
	box.add_child(_regroup)

	_preview = Tree.new()
	_preview.hide_root = true
	_preview.columns = 1
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_preview)

	confirmed.connect(func(): layout_confirmed.emit(_proposed))


func open_with(current_layout: Dictionary, actions: PackedStringArray) -> void:
	_current = current_layout
	_actions = actions
	_regroup.set_pressed_no_signal(false)
	_refresh()
	popup_centered()


func _refresh() -> void:
	_proposed = Store.propose_categories(_current, _actions, _regroup.button_pressed)
	_preview.clear()
	var root := _preview.create_item()
	var dim := get_theme_color(&"disabled_font_color", &"Editor")
	var bg := get_theme_color(&"prop_subsection", &"Editor")
	var moved := 0
	for category in _proposed.categories:
		var item := root.create_child()
		item.set_text(0, category.name)
		item.set_icon(0, get_theme_icon(&"Folder", &"EditorIcons"))
		item.set_custom_bg_color(0, bg)
		for action in category.actions:
			moved += _add_preview_action(item, action, dim)
	var leftovers := PackedStringArray()
	for action in _actions:
		if not Store.is_builtin(action) and Store.category_of(_proposed, action).is_empty():
			leftovers.append(action)
	if not leftovers.is_empty():
		var uncategorized := root.create_child()
		uncategorized.set_text(0, "Uncategorized (%d)" % leftovers.size())
		uncategorized.set_icon(0, get_theme_icon(&"Folder", &"EditorIcons"))
		uncategorized.set_custom_bg_color(0, bg)
		uncategorized.collapsed = true
		for action in leftovers:
			moved += _add_preview_action(uncategorized, action, dim)
	var new_categories := 0
	for category in _proposed.categories:
		if Store.find_category(_current, category.name).is_empty():
			new_categories += 1
	get_ok_button().disabled = moved == 0
	if moved == 0:
		_summary.text = "Nothing to change: no shared name prefixes among the affected actions."
	else:
		_summary.text = "%d actions will move. Result: %d categories (%d new)." % [
			moved, _proposed.categories.size(), new_categories]


func _add_preview_action(parent: TreeItem, action: String, dim: Color) -> int:
	var item := parent.create_child()
	item.set_text(0, action)
	var from := Store.category_of(_current, action)
	if from == Store.category_of(_proposed, action):
		item.set_custom_color(0, dim)
		return 0
	item.set_tooltip_text(0, "From: %s" % (from if not from.is_empty() else "Uncategorized"))
	return 1
