# menu_button_group.gd
# Reusable highlight/navigation helper for a vertical list of menu Buttons.
#
# Add it as a child of the menu's root CanvasItem, then call setup() with the
# buttons. It handles:
#   - "selected" highlight styling (hover stylebox + yellow font on the
#     selected button, normal stylebox + white font on the others)
#   - ui_up / ui_down / ui_accept (optionally move_up / move_down)
#   - mouse hover selecting a button, mouse click activating it
#   - touch hit-testing (activate on touch press, or on release if
#     activate_touch_on_release is set)
# and emits button_activated(index, button) when a button should fire.
#
# Input is only processed while `enabled` is true and the parent CanvasItem
# is visible in the tree. Pending touch presses are dropped whenever the group
# is disabled or its host hides, so a release after the menu reappears can't
# activate a button that was pressed before it hid.
class_name MenuButtonGroup
extends Node

signal button_activated(index: int, button: Button)
signal selection_changed(index: int)

var normal_color: Color = Color(1, 1, 1)  # White
var highlighted_color: Color = Color(1, 1, 0)  # Yellow

## When false, keyboard/touch navigation and hover-to-select are ignored.
## Button.pressed (mouse click) is still forwarded, as before the refactor.
var enabled: bool = true:
	set(value):
		enabled = value
		_touch_press_index.clear()
## Also accept the project's move_up / move_down actions for navigation.
var use_move_actions: bool = false
## Activate on touch release (inside the same button that was pressed)
## instead of on touch press. Keeps the rest of the touch gesture (and the
## emulated mouse events that follow it) from leaking to whatever is revealed
## once the menu hides.
var activate_touch_on_release: bool = false
## Mark navigation/touch events this group handled as consumed.
var consume_handled_input: bool = true

var buttons: Array[Button] = []
var current_selection: int = 0

var normal_style: StyleBox
var highlighted_style: StyleBox

# touch finger index -> button index pressed with that finger
var _touch_press_index: Dictionary = {}
# Frame in which a touch activated a button, used to ignore the duplicate
# Button.pressed produced by the emulated mouse event in that same frame.
var _touch_activation_frame: int = -1


## Registers the buttons. Styles are cached from the first button's "normal"
## and "hover" styleboxes. If highlight_initial is false every button starts
## unhighlighted (call select() later to highlight).
func setup(p_buttons: Array, highlight_initial: bool = true) -> void:
	_disconnect_buttons()
	buttons.clear()
	for b in p_buttons:
		if b is Button:
			buttons.append(b)

	current_selection = 0
	if buttons.is_empty():
		return

	normal_style = buttons[0].get_theme_stylebox("normal")
	highlighted_style = buttons[0].get_theme_stylebox("hover")

	for i in range(buttons.size()):
		var button := buttons[i]
		# Disable default focus styling; this group draws the selection.
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_entered.connect(_on_button_mouse_entered.bind(i))
		button.pressed.connect(_on_button_pressed.bind(i))

	if highlight_initial:
		update_selection()
	else:
		clear_highlight()


func _enter_tree() -> void:
	var host := get_parent() as CanvasItem
	if host and not host.visibility_changed.is_connected(_on_host_visibility_changed):
		host.visibility_changed.connect(_on_host_visibility_changed)


func _exit_tree() -> void:
	_touch_press_index.clear()
	var host := get_parent() as CanvasItem
	if host and host.visibility_changed.is_connected(_on_host_visibility_changed):
		host.visibility_changed.disconnect(_on_host_visibility_changed)


# visibility_changed also fires when an ancestor of the host hides
func _on_host_visibility_changed() -> void:
	var host := get_parent() as CanvasItem
	if host == null or not host.is_visible_in_tree():
		_touch_press_index.clear()


func _input(event: InputEvent) -> void:
	if not _is_active():
		# Backstop for hosts hidden without a visibility_changed we saw
		_touch_press_index.clear()
		return

	var handled := false

	if event.is_action_pressed("ui_down") or (use_move_actions and event.is_action_pressed("move_down")):
		move_selection(1)
		handled = true
	elif event.is_action_pressed("ui_up") or (use_move_actions and event.is_action_pressed("move_up")):
		move_selection(-1)
		handled = true
	elif event.is_action_pressed("ui_accept"):
		activate_current()
		handled = true

	if event is InputEventScreenTouch:
		handled = _handle_touch(event) or handled
	elif _is_emulated_click_on_button(event):
		# Godot dispatches the mouse click it emulates from a touch BEFORE the
		# touch itself (same frame), so the frame guard in _on_button_pressed
		# can't catch a Button.pressed raised by that click. The touch path
		# above is the only activator for touches: swallow the emulated click
		# before the Button sees it so a tap can never activate twice.
		# Always swallowed, regardless of consume_handled_input.
		if is_inside_tree():
			get_viewport().set_input_as_handled()
		return

	if handled and consume_handled_input and is_inside_tree():
		get_viewport().set_input_as_handled()


func move_selection(direction: int) -> void:
	if buttons.is_empty():
		return
	select(posmod(current_selection + direction, buttons.size()))


func select(index: int) -> void:
	if buttons.is_empty():
		return
	current_selection = clampi(index, 0, buttons.size() - 1)
	update_selection()
	selection_changed.emit(current_selection)


func update_selection() -> void:
	for i in range(buttons.size()):
		_apply_style(buttons[i], i == current_selection)


func clear_highlight() -> void:
	for button in buttons:
		_apply_style(button, false)


func activate_current() -> void:
	if buttons.is_empty() or current_selection < 0 or current_selection >= buttons.size():
		return
	button_activated.emit(current_selection, buttons[current_selection])


func _apply_style(button: Button, highlighted: bool) -> void:
	if highlighted:
		button.add_theme_stylebox_override("normal", highlighted_style)
		button.add_theme_color_override("font_color", highlighted_color)
	else:
		button.add_theme_stylebox_override("normal", normal_style)
		button.add_theme_color_override("font_color", normal_color)


# Returns true if the touch event was used by this group.
func _handle_touch(event: InputEventScreenTouch) -> bool:
	if event.pressed:
		var index := _button_at(event.position)
		if index < 0:
			return false
		select(index)
		if activate_touch_on_release:
			_touch_press_index[event.index] = index
		else:
			_activate_from_touch()
		return true

	# Release
	if not _touch_press_index.has(event.index):
		return false
	var pressed_index: int = _touch_press_index[event.index]
	_touch_press_index.erase(event.index)
	if _button_at(event.position) == pressed_index:
		select(pressed_index)
		_activate_from_touch()
	return true


func _is_emulated_click_on_button(event: InputEvent) -> bool:
	return event is InputEventMouseButton \
		and event.device == InputEvent.DEVICE_ID_EMULATION \
		and _button_at(event.position) >= 0


func _activate_from_touch() -> void:
	_touch_activation_frame = Engine.get_process_frames()
	activate_current()


func _button_at(position: Vector2) -> int:
	for i in range(buttons.size()):
		var button := buttons[i]
		if button.is_visible_in_tree() and button.get_global_rect().has_point(position):
			return i
	return -1


func _is_active() -> bool:
	if not enabled or buttons.is_empty():
		return false
	var host := get_parent() as CanvasItem
	return host == null or host.is_visible_in_tree()


func _on_button_mouse_entered(index: int) -> void:
	# Keep the selection when the mouse exits; only hover changes it.
	if enabled:
		select(index)


func _on_button_pressed(index: int) -> void:
	# Emulated clicks over the buttons are swallowed in _input; this is a
	# second guard in case one slips through in the frame a touch activated.
	if Engine.get_process_frames() == _touch_activation_frame:
		return
	if index < 0 or index >= buttons.size():
		return
	button_activated.emit(index, buttons[index])


func _disconnect_buttons() -> void:
	for button in buttons:
		if not is_instance_valid(button):
			continue
		for c in button.mouse_entered.get_connections():
			if c.callable.get_object() == self:
				button.mouse_entered.disconnect(c.callable)
		for c in button.pressed.get_connections():
			if c.callable.get_object() == self:
				button.pressed.disconnect(c.callable)
