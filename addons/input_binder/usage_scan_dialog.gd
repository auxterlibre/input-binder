@tool
extends AcceptDialog

signal action_selected(action: String)

const UsageScan := preload("res://addons/input_binder/usage_scan.gd")
const Store := preload("res://addons/input_binder/input_store.gd")

var _summary: Label
var _include_addons: CheckBox
var _results: Tree


func _init() -> void:
	title = "Scan Action Usage"
	var scale := EditorInterface.get_editor_scale()
	min_size = Vector2i(roundi(560.0 * scale), roundi(460.0 * scale))
	get_ok_button().text = "Close"

	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", roundi(6.0 * scale))
	add_child(box)

	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_summary)

	_include_addons = CheckBox.new()
	_include_addons.text = "Include other addons"
	_include_addons.tooltip_text = "Also scan res://addons/ (other plugins may reference their own optional actions)."
	_include_addons.toggled.connect(func(_pressed): _run())
	box.add_child(_include_addons)

	_results = Tree.new()
	_results.hide_root = true
	_results.columns = 1
	_results.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_results.item_activated.connect(_on_item_activated)
	box.add_child(_results)


func open_and_scan() -> void:
	popup_centered()
	_run()


func _run() -> void:
	var result := UsageScan.scan("res://", _include_addons.button_pressed, Store.list_actions())
	_summary.text = "Scanned %d scripts and %d scenes/resources. Double-click a result to jump to it." % [
		int(result.scripts), int(result.scenes)]
	_results.clear()
	var root := _results.create_item()
	var bg := get_theme_color(&"prop_subsection", &"Editor")
	var dim := get_theme_color(&"disabled_font_color", &"Editor")
	var warning := get_theme_color(&"warning_color", &"Editor")

	var unused: PackedStringArray = result.unused
	var unused_header := root.create_child()
	unused_header.set_text(0, "Unused actions (%d)" % unused.size())
	unused_header.set_custom_bg_color(0, bg)
	unused_header.set_tooltip_text(0, "Custom actions with no quoted reference in any scanned script or scene.")
	if unused.is_empty():
		var none := unused_header.create_child()
		none.set_text(0, "(none)")
		none.set_custom_color(0, dim)
	for action in unused:
		var item := unused_header.create_child()
		item.set_text(0, action)
		item.set_metadata(0, {"action": action})

	var undefined: Array = result.undefined
	var undefined_header := root.create_child()
	undefined_header.set_text(0, "Undefined action references (%d)" % undefined.size())
	undefined_header.set_custom_bg_color(0, bg)
	undefined_header.set_tooltip_text(0, "Action strings passed to Input APIs that match no defined action.")
	if undefined.is_empty():
		var none := undefined_header.create_child()
		none.set_text(0, "(none)")
		none.set_custom_color(0, dim)
	for reference in undefined:
		var item := undefined_header.create_child()
		item.set_text(0, "%s:%d - \"%s\" (%s)" % [
			String(reference.path).trim_prefix("res://"), reference.line, reference.name, reference.method])
		item.set_custom_color(0, warning)
		item.set_metadata(0, {"path": reference.path, "line": reference.line})


func _on_item_activated() -> void:
	var item := _results.get_selected()
	if item == null or not item.get_metadata(0) is Dictionary:
		return
	var meta: Dictionary = item.get_metadata(0)
	if meta.has("action"):
		hide()
		action_selected.emit(meta.action)
	elif meta.has("path"):
		hide()
		EditorInterface.edit_script(load(meta.path), meta.line)
