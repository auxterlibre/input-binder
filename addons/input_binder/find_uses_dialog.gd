@tool
extends AcceptDialog

const UsageScan := preload("res://addons/input_binder/usage_scan.gd")

var _summary: Label
var _results: Tree


func _init() -> void:
	title = "Find Uses"
	var scale := EditorInterface.get_editor_scale()
	min_size = Vector2i(roundi(560.0 * scale), roundi(380.0 * scale))
	get_ok_button().text = "Close"

	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", roundi(6.0 * scale))
	add_child(box)

	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_summary)

	_results = Tree.new()
	_results.hide_root = true
	_results.columns = 1
	_results.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_results.item_activated.connect(_on_item_activated)
	box.add_child(_results)


func open_for(action: String) -> void:
	title = "Uses of \"%s\"" % action
	var uses := UsageScan.find_uses("res://", action, false)
	if uses.is_empty():
		_summary.text = "No quoted references found (constants-based uses are not detected)."
	else:
		_summary.text = "%d quoted references in scripts, scenes and resources. Double-click to open." % uses.size()
	_results.clear()
	var root := _results.create_item()
	for use in uses:
		var item := root.create_child()
		item.set_text(0, "%s:%d    %s" % [String(use.path).trim_prefix("res://"), use.line, use.text])
		item.set_metadata(0, use)
	popup_centered()


func _on_item_activated() -> void:
	var item := _results.get_selected()
	if item == null or not item.get_metadata(0) is Dictionary:
		return
	var use: Dictionary = item.get_metadata(0)
	hide()
	var extension := String(use.path).get_extension()
	if extension == "gd":
		EditorInterface.edit_script(load(use.path), use.line)
	elif extension == "tscn":
		EditorInterface.open_scene_from_path(use.path)
