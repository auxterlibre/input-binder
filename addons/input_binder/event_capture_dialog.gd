@tool
extends ConfirmationDialog

signal event_confirmed(event: InputEvent)

var _captured: InputEvent
var _preview: Label
var _physical_check: CheckBox
var _device_option: OptionButton
var _capture_zone: PanelContainer


func _init() -> void:
	title = "Configure Input Event"
	var scale := EditorInterface.get_editor_scale()
	min_size = Vector2i(roundi(440.0 * scale), 0)

	var box := VBoxContainer.new()
	add_child(box)

	_capture_zone = PanelContainer.new()
	_capture_zone.custom_minimum_size = Vector2(0.0, 72.0 * scale)
	_capture_zone.focus_mode = Control.FOCUS_ALL
	_capture_zone.gui_input.connect(_on_zone_gui_input)
	var zone_label := Label.new()
	zone_label.text = "Press a key or gamepad input...\nClick here to bind a mouse button."
	zone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	zone_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_capture_zone.add_child(zone_label)
	box.add_child(_capture_zone)

	_preview = Label.new()
	_preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_preview)

	var options := HBoxContainer.new()
	box.add_child(options)

	_physical_check = CheckBox.new()
	_physical_check.text = "Physical key"
	_physical_check.tooltip_text = "Match by keyboard position instead of label (layout-independent)."
	_physical_check.button_pressed = true
	_physical_check.toggled.connect(func(_pressed): _update_preview())
	options.add_child(_physical_check)

	_device_option = OptionButton.new()
	_device_option.add_item("All Devices", -1)
	for i in 8:
		_device_option.add_item("Device %d" % i, i)
	_device_option.item_selected.connect(func(_index): _update_preview())
	options.add_child(_device_option)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options.add_child(spacer)

	var joy_button_menu := MenuButton.new()
	joy_button_menu.text = "Joy Button"
	joy_button_menu.flat = false
	for i in 21:
		var event := InputEventJoypadButton.new()
		event.button_index = i
		joy_button_menu.get_popup().add_item(event.as_text(), i)
	joy_button_menu.get_popup().id_pressed.connect(_on_manual_joy_button)
	options.add_child(joy_button_menu)

	var joy_axis_menu := MenuButton.new()
	joy_axis_menu.text = "Joy Axis"
	joy_axis_menu.flat = false
	for axis in 10:
		for direction in [-1.0, 1.0]:
			var event := InputEventJoypadMotion.new()
			event.axis = axis
			event.axis_value = direction
			joy_axis_menu.get_popup().add_item(event.as_text(), axis * 2 + (1 if direction > 0.0 else 0))
	joy_axis_menu.get_popup().id_pressed.connect(_on_manual_joy_axis)
	options.add_child(joy_axis_menu)

	window_input.connect(_on_window_input)
	confirmed.connect(_on_confirmed)


func open_for_capture(dialog_title: String, existing: InputEvent) -> void:
	title = dialog_title
	_captured = null
	_physical_check.button_pressed = true
	_physical_check.visible = false
	_device_option.select(0)
	if existing:
		_captured = existing.duplicate()
		if _captured is InputEventKey:
			_physical_check.visible = true
			_physical_check.button_pressed = _captured.keycode == KEY_NONE
		var device_index := _device_option.get_item_index(_captured.device)
		if device_index >= 0:
			_device_option.select(device_index)
	get_ok_button().disabled = _captured == null
	_update_preview()
	popup_centered()
	_capture_zone.grab_focus()


func _on_window_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			return
		_capture(event)
		set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed:
		_capture(event)
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.5:
		_capture(event)


func _on_zone_gui_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse and mouse.pressed:
		_capture(mouse)
		_capture_zone.accept_event()


func _on_manual_joy_button(id: int) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = id
	_capture(event)


func _on_manual_joy_axis(id: int) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = id >> 1
	event.axis_value = 1.0 if id % 2 == 1 else -1.0
	_capture(event)


func _capture(event: InputEvent) -> void:
	var clean: InputEvent = event.duplicate()
	clean.set(&"pressed", false)
	if clean is InputEventKey:
		clean.echo = false
	if clean is InputEventMouseButton:
		clean.position = Vector2.ZERO
		clean.global_position = Vector2.ZERO
		clean.button_mask = 0
		clean.double_click = false
	if clean is InputEventJoypadMotion:
		clean.axis_value = signf(clean.axis_value)
	_captured = clean
	_physical_check.visible = clean is InputEventKey
	get_ok_button().disabled = false
	_update_preview()


func _build_event() -> InputEvent:
	var event: InputEvent = _captured.duplicate()
	if event is InputEventKey:
		if _physical_check.button_pressed:
			if event.physical_keycode == KEY_NONE:
				event.physical_keycode = _captured.keycode
			event.keycode = KEY_NONE
			event.key_label = KEY_NONE
			event.unicode = 0
		else:
			if event.keycode == KEY_NONE:
				event.keycode = _captured.physical_keycode
			event.physical_keycode = KEY_NONE
			event.key_label = KEY_NONE
	event.device = _device_option.get_selected_id()
	return event


func _update_preview() -> void:
	if _captured == null:
		_preview.text = "No input captured"
		return
	var event := _build_event()
	var device := "All Devices" if event.device < 0 else "Device %d" % event.device
	_preview.text = "%s  (%s)" % [event.as_text(), device]


func _on_confirmed() -> void:
	if _captured:
		event_confirmed.emit(_build_event())
