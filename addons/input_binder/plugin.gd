@tool
extends EditorPlugin

const BinderPanel := preload("res://addons/input_binder/binder_panel.gd")
const ConstantsGen := preload("res://addons/input_binder/constants_gen.gd")

var panel: Control


func _enter_tree() -> void:
	panel = BinderPanel.new()
	panel.name = "Input Binder"
	add_control_to_container(CONTAINER_PROJECT_SETTING_TAB_RIGHT, panel)
	ConstantsGen.regenerate()
	if not OS.get_environment("IB_DEBUG").is_empty():
		var parent := panel.get_parent()
		print("DBG IB panel_parent=%s window=%s" % [
			parent.get_class() if parent else "none",
			panel.get_window().title if panel.get_window() else "none",
		])


func _exit_tree() -> void:
	remove_control_from_container(CONTAINER_PROJECT_SETTING_TAB_RIGHT, panel)
	panel.queue_free()
