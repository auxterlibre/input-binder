@tool
extends VBoxContainer

const Store := preload("res://addons/input_binder/input_store.gd")
const EventCaptureDialog := preload("res://addons/input_binder/event_capture_dialog.gd")
const AutoCategorizeDialog := preload("res://addons/input_binder/auto_categorize_dialog.gd")
const UsageScanDialog := preload("res://addons/input_binder/usage_scan_dialog.gd")
const FindUsesDialog := preload("res://addons/input_binder/find_uses_dialog.gd")
const PresetImportDialog := preload("res://addons/input_binder/preset_import_dialog.gd")
const Presets := preload("res://addons/input_binder/presets.gd")
const ConstantsGen := preload("res://addons/input_binder/constants_gen.gd")

const UNCATEGORIZED := ""

enum { BTN_ADD_EVENT, BTN_EDIT_EVENT, BTN_REMOVE }
enum { TOOL_AUTO_CATEGORIZE, TOOL_SCAN_USAGE, TOOL_EXPORT_PRESET, TOOL_IMPORT_PRESET, TOOL_TOGGLE_CONSTANTS }
enum { CTX_DUPLICATE, CTX_FIND_USES, CTX_REMOVE, CTX_REVERT_BUILTIN, CTX_SORT, CTX_EDIT_EVENT, CTX_REMOVE_EVENT }

const ASSIGN_ID_UNCATEGORIZED := 1000
const ASSIGN_ID_NEW := 1001


class BinderTree:
	extends Tree
	var panel: Control

	func _get_drag_data(at_position: Vector2) -> Variant:
		return panel.tree_drag_data(at_position, self)

	func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
		return panel.tree_can_drop(at_position, data)

	func _drop_data(at_position: Vector2, data: Variant) -> void:
		panel.tree_drop(at_position, data)


var _tree: Tree
var _search: LineEdit
var _show_builtins: CheckButton
var _event_dialog: ConfirmationDialog
var _auto_dialog: ConfirmationDialog
var _scan_dialog: AcceptDialog
var _uses_dialog: AcceptDialog
var _preset_dialog: ConfirmationDialog
var _export_dialog: EditorFileDialog
var _import_dialog: EditorFileDialog
var _tools_popup: PopupMenu
var _context_menu: PopupMenu
var _assign_menu: PopupMenu
var _assign_names: PackedStringArray
var _context_target := {}
var _name_dialog: ConfirmationDialog
var _name_edit: LineEdit
var _name_error: Label
var _name_validate: Callable
var _name_commit: Callable
var _undo := UndoRedo.new()
var _pending_event := {}
var _deadzone_before := {}
var _deadzone_token := 0
var _rebuild_queued := false
var _collapsed := {}


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(_undo):
		_undo.free()


func _ready() -> void:
	var scale := EditorInterface.get_editor_scale()

	var toolbar := HBoxContainer.new()
	add_child(toolbar)

	var add_action_button := Button.new()
	add_action_button.text = "Add Action"
	add_action_button.icon = get_theme_icon(&"Add", &"EditorIcons")
	add_action_button.pressed.connect(_on_add_action_pressed)
	toolbar.add_child(add_action_button)

	var add_category_button := Button.new()
	add_category_button.text = "Add Category"
	add_category_button.icon = get_theme_icon(&"Folder", &"EditorIcons")
	add_category_button.pressed.connect(_on_add_category_pressed)
	toolbar.add_child(add_category_button)

	var tools := MenuButton.new()
	tools.text = "Tools"
	tools.icon = get_theme_icon(&"Tools", &"EditorIcons")
	tools.flat = false
	_tools_popup = tools.get_popup()
	_tools_popup.add_item("Auto-Categorize by Prefix...", TOOL_AUTO_CATEGORIZE)
	_tools_popup.add_item("Scan Action Usage...", TOOL_SCAN_USAGE)
	_tools_popup.add_item("Export Preset...", TOOL_EXPORT_PRESET)
	_tools_popup.add_item("Import Preset...", TOOL_IMPORT_PRESET)
	_tools_popup.add_separator()
	_tools_popup.add_check_item("Auto-generate Constants File", TOOL_TOGGLE_CONSTANTS)
	_tools_popup.about_to_popup.connect(_sync_constants_check)
	_tools_popup.id_pressed.connect(_on_tools_menu)
	toolbar.add_child(tools)

	_search = LineEdit.new()
	_search.placeholder_text = "Filter by name or binding..."
	_search.clear_button_enabled = true
	_search.right_icon = get_theme_icon(&"Search", &"EditorIcons")
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_text): _rebuild())
	toolbar.add_child(_search)

	_show_builtins = CheckButton.new()
	_show_builtins.text = "Built-ins"
	_show_builtins.tooltip_text = "Show Godot's built-in ui_* actions."
	_show_builtins.button_pressed = EditorInterface.get_editor_settings().get_project_metadata(
		"input_binder", "show_builtins", false)
	_show_builtins.toggled.connect(_on_show_builtins_toggled)
	toolbar.add_child(_show_builtins)

	var binder_tree := BinderTree.new()
	binder_tree.panel = self
	_tree = binder_tree
	_tree.hide_root = true
	_tree.columns = 2
	_tree.set_column_titles_visible(true)
	_tree.set_column_title(0, "Action")
	_tree.set_column_title(1, "Deadzone")
	_tree.set_column_expand(0, true)
	_tree.set_column_expand(1, false)
	_tree.set_column_custom_minimum_width(1, roundi(90.0 * scale))
	_tree.drop_mode_flags = Tree.DROP_MODE_INBETWEEN | Tree.DROP_MODE_ON_ITEM
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.item_edited.connect(_on_item_edited)
	_tree.button_clicked.connect(_on_button_clicked)
	_tree.allow_rmb_select = true
	_tree.item_mouse_selected.connect(_on_item_mouse_selected)
	add_child(_tree)

	_event_dialog = EventCaptureDialog.new()
	_event_dialog.event_confirmed.connect(_on_event_confirmed)
	add_child(_event_dialog)

	_auto_dialog = AutoCategorizeDialog.new()
	_auto_dialog.layout_confirmed.connect(_on_auto_layout_confirmed)
	add_child(_auto_dialog)

	_scan_dialog = UsageScanDialog.new()
	_scan_dialog.action_selected.connect(_on_scan_action_selected)
	add_child(_scan_dialog)

	_uses_dialog = FindUsesDialog.new()
	add_child(_uses_dialog)

	_preset_dialog = PresetImportDialog.new()
	_preset_dialog.preset_confirmed.connect(_on_preset_confirmed)
	add_child(_preset_dialog)

	_export_dialog = EditorFileDialog.new()
	_export_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	_export_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	_export_dialog.add_filter("*.inputpreset", "Input Binder Preset")
	_export_dialog.file_selected.connect(_on_export_path_selected)
	add_child(_export_dialog)

	_import_dialog = EditorFileDialog.new()
	_import_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	_import_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	_import_dialog.add_filter("*.inputpreset", "Input Binder Preset")
	_import_dialog.file_selected.connect(_on_import_path_selected)
	add_child(_import_dialog)

	_context_menu = PopupMenu.new()
	_context_menu.id_pressed.connect(_on_context_menu)
	add_child(_context_menu)
	_assign_menu = PopupMenu.new()
	_assign_menu.id_pressed.connect(_on_assign_menu)
	_context_menu.add_child(_assign_menu)

	_name_dialog = ConfirmationDialog.new()
	var name_box := VBoxContainer.new()
	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size.x = 280.0 * scale
	_name_edit.text_changed.connect(_on_name_text_changed)
	name_box.add_child(_name_edit)
	_name_error = Label.new()
	_name_error.add_theme_color_override(&"font_color", get_theme_color(&"error_color", &"Editor"))
	name_box.add_child(_name_error)
	_name_dialog.add_child(name_box)
	_name_dialog.register_text_enter(_name_edit)
	_name_dialog.confirmed.connect(_on_name_confirmed)
	add_child(_name_dialog)

	ProjectSettings.settings_changed.connect(_on_settings_changed)
	visibility_changed.connect(_queue_rebuild)
	_rebuild()
	if not OS.get_environment("IB_DEBUG").is_empty():
		print("DBG IB panel_ready actions=%d categories=%d" % [
			Store.list_actions().size(), Store.get_layout().categories.size()])


func _shortcut_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or not key.is_command_or_control_pressed():
		return
	if key.keycode == KEY_Z and not key.shift_pressed:
		if _undo.undo():
			accept_event()
	elif key.keycode == KEY_Y or (key.keycode == KEY_Z and key.shift_pressed):
		if _undo.redo():
			accept_event()


func _on_settings_changed() -> void:
	if _deadzone_before.is_empty():
		_queue_rebuild()


func _queue_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	_do_rebuild.call_deferred()


func _do_rebuild() -> void:
	_rebuild_queued = false
	_rebuild()


func _rebuild() -> void:
	if _tree == null:
		return
	var selected_meta := {}
	var selected := _tree.get_selected()
	if selected and selected.get_metadata(0) is Dictionary:
		selected_meta = selected.get_metadata(0)

	var scroll := _tree.get_scroll()
	if _tree.get_root():
		_remember_collapsed(_tree.get_root())

	_tree.clear()
	var root := _tree.create_item()
	var layout := Store.get_layout()
	var all_actions := Store.list_actions()
	var show_builtins: bool = _show_builtins.button_pressed
	var filter: String = _search.text.strip_edges().to_lower()
	var conflicts := _conflict_map(all_actions)

	var assigned := {}
	for category in layout.categories:
		for action in category.actions:
			assigned[action] = true
	var uncategorized := []
	for action in all_actions:
		if not assigned.has(action):
			uncategorized.append(action)

	_add_category_item(root, UNCATEGORIZED, uncategorized, all_actions, show_builtins, filter, conflicts)
	for category in layout.categories:
		_add_category_item(root, category.name, category.actions, all_actions, show_builtins, filter, conflicts)

	if not selected_meta.is_empty():
		var item := _find_item(root, selected_meta)
		if item:
			item.select(0)
			_tree.scroll_to_item(item)
	_restore_scroll.call_deferred(scroll)


func _restore_scroll(scroll: Vector2) -> void:
	if _tree:
		_tree.get_v_scroll_bar().value = scroll.y


func _remember_collapsed(item: TreeItem) -> void:
	for child in item.get_children():
		if child.get_child_count() > 0:
			_collapsed[str(child.get_metadata(0))] = child.collapsed
			_remember_collapsed(child)


func _apply_collapsed(item: TreeItem) -> void:
	item.collapsed = _collapsed.get(str(item.get_metadata(0)), false)


func _add_category_item(root: TreeItem, category_name: String, actions: Array,
		all_actions: PackedStringArray, show_builtins: bool, filter: String, conflicts: Dictionary) -> void:
	var visible_actions := []
	for action in actions:
		if not action in all_actions:
			continue
		if not show_builtins and Store.is_builtin(action):
			continue
		if not filter.is_empty() and not _matches_filter(action, filter):
			continue
		visible_actions.append(action)
	if visible_actions.is_empty() and (category_name == UNCATEGORIZED or not filter.is_empty()):
		return

	var item := root.create_child()
	item.set_text(0, category_name if category_name != UNCATEGORIZED else "Uncategorized")
	item.set_metadata(0, {"kind": "category", "name": category_name})
	item.set_icon(0, get_theme_icon(&"Folder", &"EditorIcons"))
	var bg := get_theme_color(&"prop_subsection", &"Editor")
	item.set_custom_bg_color(0, bg)
	item.set_custom_bg_color(1, bg)
	item.set_selectable(1, false)
	if category_name != UNCATEGORIZED:
		item.set_editable(0, true)
		item.add_button(0, get_theme_icon(&"Remove", &"EditorIcons"), BTN_REMOVE, false,
			"Remove category (its actions become uncategorized)")
	for action in visible_actions:
		_add_action_item(item, action, conflicts)
	_apply_collapsed(item)


func _add_action_item(parent: TreeItem, action: String, conflicts: Dictionary) -> void:
	var data := Store.get_action(action)
	var item := parent.create_child()
	item.set_text(0, action)
	item.set_metadata(0, {"kind": "action", "action": action})
	var builtin := Store.is_builtin(action)
	if builtin:
		item.set_custom_color(0, get_theme_color(&"disabled_font_color", &"Editor"))
	else:
		item.set_editable(0, true)
	item.set_cell_mode(1, TreeItem.CELL_MODE_RANGE)
	item.set_range_config(1, 0.0, 1.0, 0.01)
	item.set_range(1, data.deadzone)
	item.set_editable(1, true)
	item.add_button(0, get_theme_icon(&"Add", &"EditorIcons"), BTN_ADD_EVENT, false, "Add event")
	if not builtin:
		item.add_button(0, get_theme_icon(&"Remove", &"EditorIcons"), BTN_REMOVE, false, "Remove action")
	for i in data.events.size():
		_add_event_item(item, action, i, data.events[i], conflicts)
	_apply_collapsed(item)


func _add_event_item(parent: TreeItem, action: String, index: int, event: InputEvent,
		conflicts: Dictionary) -> void:
	var item := parent.create_child()
	item.set_text(0, event.as_text())
	item.set_metadata(0, {"kind": "event", "action": action, "index": index})
	item.set_icon(0, _event_icon(event))
	item.set_selectable(1, false)
	item.add_button(0, get_theme_icon(&"Edit", &"EditorIcons"), BTN_EDIT_EVENT, false, "Edit event")
	item.add_button(0, get_theme_icon(&"Remove", &"EditorIcons"), BTN_REMOVE, false, "Remove event")

	var bound_count := 0
	var others := PackedStringArray()
	for bound_action in conflicts.get(event.as_text(), []):
		if bound_action == action:
			bound_count += 1
		elif not bound_action in others:
			others.append(bound_action)
	if not others.is_empty() or bound_count > 1:
		item.set_custom_color(0, get_theme_color(&"warning_color", &"Editor"))
		var problems := PackedStringArray()
		if bound_count > 1:
			problems.append("bound more than once in this action")
		if not others.is_empty():
			problems.append("also bound to: " + ", ".join(others))
		item.set_tooltip_text(0, "This input is " + "; ".join(problems) + ".")


func _event_icon(event: InputEvent) -> Texture2D:
	if event is InputEventKey:
		return get_theme_icon(&"KeyboardPhysical" if event.keycode == KEY_NONE else &"Keyboard", &"EditorIcons")
	if event is InputEventMouseButton:
		return get_theme_icon(&"Mouse", &"EditorIcons")
	if event is InputEventJoypadButton:
		return get_theme_icon(&"JoyButton", &"EditorIcons")
	if event is InputEventJoypadMotion:
		return get_theme_icon(&"JoyAxis", &"EditorIcons")
	return get_theme_icon(&"Object", &"EditorIcons")


func _matches_filter(action: String, filter: String) -> bool:
	if action.to_lower().contains(filter):
		return true
	for event in Store.get_action(action).events:
		if event.as_text().to_lower().contains(filter):
			return true
	return false


func _conflict_map(all_actions: PackedStringArray) -> Dictionary:
	var map := {}
	for action in all_actions:
		if Store.is_builtin(action):
			continue
		for event in Store.get_action(action).events:
			var key: String = event.as_text()
			if not map.has(key):
				map[key] = []
			map[key].append(action)
	return map


func _find_item(item: TreeItem, meta: Dictionary) -> TreeItem:
	for child in item.get_children():
		if child.get_metadata(0) == meta:
			return child
		var found := _find_item(child, meta)
		if found:
			return found
	return null


func _selected_category() -> String:
	var item := _tree.get_selected()
	while item:
		var meta = item.get_metadata(0)
		if meta is Dictionary and meta.kind == "category":
			return meta.name
		item = item.get_parent()
	return UNCATEGORIZED


func _commit(description: String, before: Dictionary) -> void:
	var after := Store.snapshot()
	_undo.create_action(description)
	_undo.add_do_method(_apply.bind(after))
	_undo.add_undo_method(_apply.bind(before))
	_undo.commit_action()


func _apply(snap: Dictionary) -> void:
	Store.restore(snap)
	Store.save()
	ConstantsGen.regenerate()
	_queue_rebuild()


func _on_add_action_pressed() -> void:
	_open_name_dialog("Add Action", "new_action", _validate_new_action_name, _create_action_named)


func _on_add_category_pressed() -> void:
	_open_name_dialog("Add Category", "New Category", _validate_category_name, _create_category_named)


func _on_tools_menu(id: int) -> void:
	if id == TOOL_AUTO_CATEGORIZE:
		_auto_dialog.open_with(Store.get_layout(), Store.list_actions())
	elif id == TOOL_SCAN_USAGE:
		_scan_dialog.open_and_scan()
	elif id == TOOL_EXPORT_PRESET:
		_export_dialog.current_file = "inputs.inputpreset"
		_export_dialog.popup_centered_ratio(0.7)
	elif id == TOOL_IMPORT_PRESET:
		_import_dialog.popup_centered_ratio(0.7)
	elif id == TOOL_TOGGLE_CONSTANTS:
		ConstantsGen.set_enabled(not ConstantsGen.enabled())
		if ConstantsGen.enabled():
			ConstantsGen.regenerate()
		_sync_constants_check()


func _sync_constants_check() -> void:
	var index := _tools_popup.get_item_index(TOOL_TOGGLE_CONSTANTS)
	_tools_popup.set_item_checked(index, ConstantsGen.enabled())


func _on_auto_layout_confirmed(proposed: Dictionary) -> void:
	var before := Store.snapshot()
	Store.set_layout(proposed)
	_commit("Auto-Categorize Actions", before)


func _on_scan_action_selected(action: String) -> void:
	if not _search.text.is_empty():
		_search.clear()
	var item := _find_item(_tree.get_root(), {"kind": "action", "action": action})
	if item:
		item.select(0)
		_tree.scroll_to_item(item)


func _on_export_path_selected(path: String) -> void:
	if Presets.save_preset(path) != OK:
		push_warning("Input Binder: could not write preset to " + path)


func _on_import_path_selected(path: String) -> void:
	var data := Presets.load_preset(path)
	if data.is_empty():
		push_warning("Input Binder: not a valid Input Binder preset: " + path)
		return
	_preset_dialog.open_with(data)


func _on_preset_confirmed(data: Dictionary, overwrite: bool) -> void:
	var before := Store.snapshot()
	Presets.apply_preset(data, overwrite)
	_commit("Import Input Preset", before)


func _on_item_mouse_selected(click_position: Vector2, mouse_button: int) -> void:
	if mouse_button != MOUSE_BUTTON_RIGHT:
		return
	var item := _tree.get_selected()
	if item == null or not item.get_metadata(0) is Dictionary:
		return
	_context_target = item.get_metadata(0)
	_context_menu.clear()
	var kind: String = _context_target.kind
	if kind == "action":
		_fill_assign_menu()
		_context_menu.add_submenu_node_item("Assign to Category", _assign_menu)
		if not Store.is_builtin(_context_target.action):
			_context_menu.add_item("Duplicate", CTX_DUPLICATE)
		_context_menu.add_item("Find Uses...", CTX_FIND_USES)
		_context_menu.add_separator()
		if Store.is_builtin(_context_target.action):
			_context_menu.add_item("Revert to Default", CTX_REVERT_BUILTIN)
			_context_menu.set_item_disabled(_context_menu.get_item_index(CTX_REVERT_BUILTIN),
				not Store.is_builtin_customized(_context_target.action))
		else:
			_context_menu.add_item("Remove", CTX_REMOVE)
	elif kind == "category":
		if _context_target.name == UNCATEGORIZED:
			return
		_context_menu.add_item("Sort Actions A-Z", CTX_SORT)
		_context_menu.add_item("Remove Category", CTX_REMOVE)
	elif kind == "event":
		_context_menu.add_item("Edit Event...", CTX_EDIT_EVENT)
		_context_menu.add_item("Remove Event", CTX_REMOVE_EVENT)
	_context_menu.popup(Rect2i(Vector2i(_tree.get_screen_position() + click_position), Vector2i.ZERO))


func _fill_assign_menu() -> void:
	_assign_menu.clear()
	var layout := Store.get_layout()
	_assign_names = Store.category_names(layout)
	var current := Store.category_of(layout, _context_target.action)
	for i in _assign_names.size():
		_assign_menu.add_item(_assign_names[i], i)
		_assign_menu.set_item_disabled(i, _assign_names[i] == current)
	_assign_menu.add_item("Uncategorized", ASSIGN_ID_UNCATEGORIZED)
	_assign_menu.set_item_disabled(_assign_menu.get_item_index(ASSIGN_ID_UNCATEGORIZED), current.is_empty())
	_assign_menu.add_separator()
	_assign_menu.add_item("New Category...", ASSIGN_ID_NEW)


func _on_assign_menu(id: int) -> void:
	if id == ASSIGN_ID_NEW:
		_open_name_dialog("New Category", "New Category", _validate_category_name, _create_category_and_assign)
		return
	var before := Store.snapshot()
	var layout := Store.get_layout()
	if id == ASSIGN_ID_UNCATEGORIZED:
		Store.unassign(layout, _context_target.action)
	else:
		Store.assign(layout, _context_target.action, _assign_names[id])
	Store.set_layout(layout)
	_commit("Move Input Action", before)


func _create_category_and_assign(name: String) -> void:
	var before := Store.snapshot()
	var layout := Store.get_layout()
	var created := Store.add_category(layout, name)
	Store.assign(layout, _context_target.action, created)
	Store.set_layout(layout)
	_commit("Move Input Action", before)


func _on_context_menu(id: int) -> void:
	var meta := _context_target
	if id == CTX_DUPLICATE:
		_duplicate_action(meta.action)
	elif id == CTX_FIND_USES:
		_uses_dialog.open_for(meta.action)
	elif id == CTX_REMOVE and meta.kind == "action":
		_remove_action(meta.action)
	elif id == CTX_REVERT_BUILTIN:
		_revert_builtin(meta.action)
	elif id == CTX_SORT:
		_sort_category(meta.name)
	elif id == CTX_REMOVE and meta.kind == "category":
		_remove_category(meta.name)
	elif id == CTX_EDIT_EVENT:
		_pending_event = {"action": meta.action, "index": meta.index}
		var events: Array = Store.get_action(meta.action).events
		_event_dialog.open_for_capture("Edit Event - %s" % meta.action, events[meta.index])
	elif id == CTX_REMOVE_EVENT:
		_remove_event(meta.action, meta.index)


func _duplicate_action(action: String) -> void:
	var n := 2
	while Store.has_action("%s_%d" % [action, n]):
		n += 1
	var new_name := "%s_%d" % [action, n]
	var before := Store.snapshot()
	var data := Store.get_action(action)
	Store.set_action(new_name, data.deadzone, data.events)
	var layout := Store.get_layout()
	var category := Store.category_of(layout, action)
	if not category.is_empty():
		var index: int = Store.find_category(layout, category).actions.find(action)
		Store.assign(layout, new_name, category, index + 1)
		Store.set_layout(layout)
	_commit("Duplicate Input Action", before)


func _revert_builtin(action: String) -> void:
	var before := Store.snapshot()
	Store.revert_builtin(action)
	_commit("Revert Built-in Action", before)


func _sort_category(name: String) -> void:
	var before := Store.snapshot()
	var layout := Store.get_layout()
	var category := Store.find_category(layout, name)
	if category.is_empty():
		return
	category.actions.sort_custom(func(a, b): return String(a).naturalnocasecmp_to(String(b)) < 0)
	Store.set_layout(layout)
	_commit("Sort Category", before)


func _validate_new_action_name(name: String) -> String:
	var error := Store.action_name_error(name)
	if not error.is_empty():
		return error
	if name.begins_with("ui_"):
		return "Names starting with 'ui_' are reserved for built-in actions."
	if Store.has_action(name):
		return "An action named '%s' already exists." % name
	return ""


func _validate_category_name(name: String) -> String:
	if name.strip_edges().is_empty():
		return "Name cannot be empty."
	return ""


func _open_name_dialog(title: String, initial: String, validate: Callable, commit: Callable) -> void:
	_name_validate = validate
	_name_commit = commit
	_name_dialog.title = title
	_name_edit.text = initial
	_on_name_text_changed(initial)
	_name_dialog.popup_centered()
	_name_edit.grab_focus()
	_name_edit.select_all()


func _on_name_text_changed(text: String) -> void:
	var error: String = _name_validate.call(text.strip_edges())
	_name_error.text = error
	_name_dialog.get_ok_button().disabled = not error.is_empty()


func _on_name_confirmed() -> void:
	var name := _name_edit.text.strip_edges()
	if not String(_name_validate.call(name)).is_empty():
		return
	_name_commit.call(name)


func _create_action_named(action: String) -> void:
	var before := Store.snapshot()
	Store.add_action(action)
	var target := _selected_category()
	if target != UNCATEGORIZED:
		var layout := Store.get_layout()
		Store.assign(layout, action, target)
		Store.set_layout(layout)
	_commit("Add Input Action", before)


func _create_category_named(name: String) -> void:
	var before := Store.snapshot()
	var layout := Store.get_layout()
	Store.add_category(layout, name)
	Store.set_layout(layout)
	_commit("Add Category", before)


func _on_button_clicked(item: TreeItem, _column: int, id: int, mouse_button: int) -> void:
	if mouse_button != MOUSE_BUTTON_LEFT:
		return
	var meta: Dictionary = item.get_metadata(0)
	var kind: String = meta.kind
	if kind == "category" and id == BTN_REMOVE:
		_remove_category(meta.name)
	elif kind == "action" and id == BTN_ADD_EVENT:
		_pending_event = {"action": meta.action, "index": -1}
		_event_dialog.open_for_capture("Add Event - %s" % meta.action, null)
	elif kind == "action" and id == BTN_REMOVE:
		_remove_action(meta.action)
	elif kind == "event" and id == BTN_EDIT_EVENT:
		_pending_event = {"action": meta.action, "index": meta.index}
		var events: Array = Store.get_action(meta.action).events
		_event_dialog.open_for_capture("Edit Event - %s" % meta.action, events[meta.index])
	elif kind == "event" and id == BTN_REMOVE:
		_remove_event(meta.action, meta.index)


func _remove_category(name: String) -> void:
	var before := Store.snapshot()
	var layout := Store.get_layout()
	Store.remove_category(layout, name)
	Store.set_layout(layout)
	_commit("Remove Category", before)


func _remove_action(action: String) -> void:
	var before := Store.snapshot()
	var layout := Store.get_layout()
	Store.unassign(layout, action)
	Store.set_layout(layout)
	Store.remove_action(action)
	_commit("Remove Input Action", before)


func _remove_event(action: String, index: int) -> void:
	var before := Store.snapshot()
	var data := Store.get_action(action)
	data.events.remove_at(index)
	Store.set_action(action, data.deadzone, data.events)
	_commit("Remove Event", before)


func _on_event_confirmed(event: InputEvent) -> void:
	if _pending_event.is_empty():
		return
	var before := Store.snapshot()
	var data := Store.get_action(_pending_event.action)
	var index: int = _pending_event.index
	if index < 0:
		data.events.append(event)
	else:
		data.events[index] = event
	Store.set_action(_pending_event.action, data.deadzone, data.events)
	_commit("Change Event" if index >= 0 else "Add Event", before)
	_pending_event = {}


func _on_item_edited() -> void:
	var item := _tree.get_edited()
	if item == null:
		return
	var meta: Dictionary = item.get_metadata(0)
	if meta.kind == "action" and _tree.get_edited_column() == 1:
		_edit_deadzone(meta.action, item.get_range(1))
	elif meta.kind == "action":
		_apply_action_rename(meta.action, item.get_text(0).strip_edges())
	elif meta.kind == "category":
		_apply_category_rename(meta.name, item.get_text(0).strip_edges())


func _edit_deadzone(action: String, value: float) -> void:
	if _deadzone_before.is_empty():
		_deadzone_before = Store.snapshot()
	var data := Store.get_action(action)
	Store.set_action(action, value, data.events)
	_deadzone_token += 1
	var token := _deadzone_token
	await get_tree().create_timer(0.5).timeout
	if token != _deadzone_token:
		return
	var before := _deadzone_before
	_deadzone_before = {}
	_commit("Change Deadzone", before)


func _apply_action_rename(old_name: String, new_name: String) -> void:
	if new_name == old_name:
		return
	var error := _validate_new_action_name(new_name)
	if not error.is_empty():
		push_warning("Input Binder: cannot rename '%s': %s" % [old_name, error])
		_queue_rebuild()
		return
	var before := Store.snapshot()
	Store.rename_action(old_name, new_name)
	var layout := Store.get_layout()
	Store.rename_in_layout(layout, old_name, new_name)
	Store.set_layout(layout)
	_commit("Rename Input Action", before)


func _apply_category_rename(old_name: String, new_name: String) -> void:
	if new_name == old_name or new_name.strip_edges().is_empty():
		_queue_rebuild()
		return
	var before := Store.snapshot()
	var layout := Store.get_layout()
	Store.rename_category(layout, old_name, Store.unique_category_name(layout, new_name))
	Store.set_layout(layout)
	_commit("Rename Category", before)


func _on_show_builtins_toggled(pressed: bool) -> void:
	EditorInterface.get_editor_settings().set_project_metadata("input_binder", "show_builtins", pressed)
	_rebuild()


func tree_drag_data(at_position: Vector2, tree: Tree) -> Variant:
	var item := tree.get_item_at_position(at_position)
	if item == null:
		return null
	var meta = item.get_metadata(0)
	if not meta is Dictionary or meta.kind == "event":
		return null
	if meta.kind == "category" and meta.name == UNCATEGORIZED:
		return null
	var preview := Label.new()
	preview.text = item.get_text(0)
	tree.set_drag_preview(preview)
	return {"input_binder": true, "kind": meta.kind, "name": meta.get("name", ""), "action": meta.get("action", "")}


func tree_can_drop(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("input_binder", false)


func tree_drop(at_position: Vector2, data: Variant) -> void:
	if not (data is Dictionary and data.get("input_binder", false)):
		return
	var item := _tree.get_item_at_position(at_position)
	var section := _tree.get_drop_section_at_position(at_position)
	if data.kind == "action":
		_drop_action(data.action, item, section)
	elif data.kind == "category":
		_drop_category(data.name, item, section)


func _drop_action(action: String, item: TreeItem, section: int) -> void:
	var layout := Store.get_layout()
	var target_category := UNCATEGORIZED
	var target_index := -1
	if item:
		var meta: Dictionary = item.get_metadata(0)
		if meta.kind == "event":
			item = item.get_parent()
			meta = item.get_metadata(0)
		if meta.kind == "category":
			target_category = meta.name
		elif meta.kind == "action":
			var parent_meta: Dictionary = item.get_parent().get_metadata(0)
			target_category = parent_meta.name
			if target_category != UNCATEGORIZED:
				var actions: Array = Store.find_category(layout, target_category).actions
				target_index = actions.find(meta.action)
				if section >= 0:
					target_index += 1
				var old_index := actions.find(action)
				if old_index >= 0 and old_index < target_index:
					target_index -= 1
	if target_category == UNCATEGORIZED and Store.category_of(layout, action) == UNCATEGORIZED:
		return
	var before := Store.snapshot()
	Store.unassign(layout, action)
	if target_category != UNCATEGORIZED:
		Store.assign(layout, action, target_category, target_index)
	Store.set_layout(layout)
	_commit("Move Input Action", before)


func _drop_category(name: String, item: TreeItem, section: int) -> void:
	while item and not (item.get_metadata(0) is Dictionary and item.get_metadata(0).kind == "category"):
		item = item.get_parent()
	if item == null:
		return
	var target_name: String = item.get_metadata(0).name
	if target_name == name:
		return
	var layout := Store.get_layout()
	var names := Store.category_names(layout)
	var target_index := 0
	if target_name != UNCATEGORIZED:
		target_index = names.find(target_name)
		if section > 0:
			target_index += 1
		var old_index := names.find(name)
		if old_index >= 0 and old_index < target_index:
			target_index -= 1
	if target_index == names.find(name):
		return
	var before := Store.snapshot()
	Store.move_category(layout, name, target_index)
	Store.set_layout(layout)
	_commit("Reorder Categories", before)
