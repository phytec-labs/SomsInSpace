extends Control

@onready var line_edit = $VBoxContainer/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/NameInput/LineEdit
@onready var submit_button = $VBoxContainer/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/NameInput/SubmitButton
@onready var result_label = $VBoxContainer/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ResultLabel
@onready var info_label = $VBoxContainer/InfoLabel
@onready var debug_label = $VBoxContainer/DebugInfo

func _ready():
	# Connect submit button
	submit_button.pressed.connect(_on_submit_button_pressed)
	
	# Connect text submission from LineEdit (handles Enter key)
	line_edit.text_submitted.connect(_on_text_submitted)
	
	# Make sure virtual keyboard is enabled
	line_edit.virtual_keyboard_enabled = true
	
	# Set focus mode
	line_edit.focus_mode = Control.FOCUS_CLICK
	
	# Debug info
	OS.open_midi_inputs()
	print("OS: ", OS.get_name())
	print("Connected joypads: ", Input.get_connected_joypads())
	print("Touch screen: ", DisplayServer.is_touchscreen_available())
	
	info_label.text = "Touch input status: Ready (emulated from mouse: " + str(Input.is_emulating_touch_from_mouse()) + ")"

func _input(event: InputEvent) -> void:
	# Record all input events for debugging
	debug_label.text = "Debug: " + str(event.get_class())
	
	# Handle screen touch input
	if event is InputEventScreenTouch:
		debug_label.text = "Debug: Screen Touch at " + str(event.position) + " (pressed: " + str(event.pressed) + ")"
		
		if event.pressed:
			# Check if the line edit was touched
			if line_edit.get_global_rect().has_point(event.position):
				info_label.text = "Touch input: LineEdit touched"
				line_edit.grab_focus()
				get_viewport().set_input_as_handled()
				return
				
			# Check if the submit button was touched
			if submit_button.get_global_rect().has_point(event.position):
				info_label.text = "Touch input: Submit button touched"
				_on_submit_button_pressed()
				get_viewport().set_input_as_handled()
				return
	
	# Also handle mouse input for testing on desktop
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		debug_label.text = "Debug: Mouse Click at " + str(event.position)
		
		# Check if the line edit was clicked
		if line_edit.get_global_rect().has_point(event.position):
			info_label.text = "Mouse input: LineEdit clicked"
			line_edit.grab_focus()
			return
			
		# Check if the submit button was clicked
		if submit_button.get_global_rect().has_point(event.position):
			info_label.text = "Mouse input: Submit button clicked"
			# The button's pressed signal will handle this
			return

func _on_submit_button_pressed():
	handle_submission(line_edit.text)
	
func _on_text_submitted(text: String):
	handle_submission(text)

func handle_submission(text: String):
	# Release focus
	line_edit.release_focus()
	
	# Process the text
	var processed_name = text.strip_edges()
	if processed_name.is_empty():
		processed_name = "Anonymous"
	
	# Update result label
	result_label.text = "Hello, " + processed_name + "!"
	info_label.text = "Input submitted: '" + processed_name + "'"
	
	# Optional: clear the text field
	line_edit.text = ""
	
	print("Submission processed: " + processed_name)
