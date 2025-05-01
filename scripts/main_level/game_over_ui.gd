# game_over_ui.gd
extends Control

signal retry_pressed
signal main_menu_pressed

@onready var height_label = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ScoreContainer/HeightLabel
@onready var score_label = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ScoreContainer/ScoreLabel
@onready var retry_button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ButtonContainer/RetryButton
@onready var main_menu_button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ButtonContainer/MainMenuButton

# New UI components
@onready var name_input = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/NameInput/LineEdit
@onready var submit_button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/NameInput/SubmitButton
@onready var scoreboard_container = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ScoreboardContainer
@onready var scoreboard_list = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ScoreboardContainer/ScoreboardList

var buttons: Array[Button]
var current_selection: int = 0
var current_final_height: float = 0
var current_final_score: int = 0
var scoreboard_manager = null

# Style variables
var normal_style: StyleBoxFlat
var highlighted_style: StyleBoxFlat
var normal_color = Color(1, 1, 1)  # White
var highlighted_color = Color(1, 1, 0)  # Yellow

# UI States
enum UIState { SCORE_INPUT, SCOREBOARD_VIEW }
var current_state: UIState = UIState.SCORE_INPUT

func _ready():
	# Ensure all required nodes are present
	assert(retry_button != null, "retry_button not found")
	assert(main_menu_button != null, "main_menu_button not found")
	assert(name_input != null, "name_input LineEdit not found")
	assert(submit_button != null, "submit_button not found")
	assert(scoreboard_list != null, "scoreboard_list not found")

	# Get the scoreboard manager
	scoreboard_manager = get_node("/root/ScoreboardManager")
	assert(scoreboard_manager != null, "ScoreboardManager singleton not found")
	
	# Initialize buttons array
	buttons = [retry_button, main_menu_button]

	# Get styles from the first button
	normal_style = retry_button.get_theme_stylebox("normal")
	highlighted_style = retry_button.get_theme_stylebox("hover")

	# Connect signals
	for button in buttons:
		# Disable default focus styling
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_entered.connect(_on_button_hover.bind(buttons.find(button)))
		button.mouse_exited.connect(_on_button_mouse_exit)
		button.pressed.connect(_on_button_pressed.bind(button))
	
	# Connect submit button
	submit_button.pressed.connect(_on_submit_button_pressed)
	
	# Connect name input events to handle Enter key
	name_input.text_submitted.connect(_on_name_submitted)
	
	# Connect visibility signal
	visibility_changed.connect(_on_visibility_changed)
	
	# Initially hide the scoreboard
	set_ui_state(UIState.SCORE_INPUT)
	
	# Initially hide the screen
	hide()

func _input(event: InputEvent) -> void:
	if not visible or buttons.is_empty():
		return

	if current_state == UIState.SCOREBOARD_VIEW:
		if event.is_action_pressed("ui_down") or event.is_action_pressed("move_down"):
			move_selection(1)
		elif event.is_action_pressed("ui_up") or event.is_action_pressed("move_up"):
			move_selection(-1)
		elif event.is_action_pressed("ui_accept"):
			select_current_item()
	
	# Add touch input handling
	if event is InputEventScreenTouch and event.pressed:
		_handle_touch(event.position)

func _handle_touch(position: Vector2) -> void:
	if current_state == UIState.SCOREBOARD_VIEW:
		for i in range(buttons.size()):
			if buttons[i].get_global_rect().has_point(position):
				current_selection = i
				update_selection()
				select_current_item()
				break

func move_selection(direction: int) -> void:
	if buttons.is_empty() or current_state != UIState.SCOREBOARD_VIEW:
		return

	current_selection = (current_selection + direction) % buttons.size()
	if current_selection < 0:
		current_selection = buttons.size() - 1
	update_selection()

func update_selection() -> void:
	if buttons.is_empty() or current_state != UIState.SCOREBOARD_VIEW:
		return

	for i in range(buttons.size()):
		var button = buttons[i]
		if i == current_selection:
			button.add_theme_stylebox_override("normal", highlighted_style)
			button.add_theme_color_override("font_color", highlighted_color)
		else:
			button.add_theme_stylebox_override("normal", normal_style)
			button.add_theme_color_override("font_color", normal_color)

func select_current_item() -> void:
	if buttons.is_empty() or current_state != UIState.SCOREBOARD_VIEW:
		return

	var selected_button = buttons[current_selection]
	_on_button_pressed(selected_button)

func set_final_height(height: float) -> void:
	current_final_height = height
	if height_label:
		height_label.text = scoreboard_manager.format_height(height)

func set_final_score(score: int) -> void:
	current_final_score = score
	if score_label:
		score_label.text = scoreboard_manager.format_points(score)

func _on_button_pressed(button: Button) -> void:
	match button:
		retry_button:
			retry_pressed.emit()
		main_menu_button:
			main_menu_pressed.emit()

func _on_button_hover(index: int) -> void:
	if current_state == UIState.SCOREBOARD_VIEW:
		current_selection = index
		update_selection()

func _on_button_mouse_exit() -> void:
	# Optional: If you want the selection to stay when mouse exits,
	# leave this empty. Remove this function if you don't need it.
	pass

func _on_visibility_changed() -> void:
	if visible:
		# Reset UI state
		if name_input:
			name_input.text = ""  # Clear any previous text
			
		# Check if the score would make it to the leaderboard
		var would_make_leaderboard = scoreboard_manager.would_make_leaderboard(current_final_height, current_final_score)
		
		# If the score would make the leaderboard, show name input
		if would_make_leaderboard:
			set_ui_state(UIState.SCORE_INPUT)
			# Focus on the name input field
			if name_input:
				name_input.grab_focus()
		else:
			# Score wouldn't make leaderboard, skip name input and show scoreboard
			populate_scoreboard()
			set_ui_state(UIState.SCOREBOARD_VIEW)

func _on_submit_button_pressed() -> void:
	submit_score()

func _on_name_submitted(_text: String) -> void:
	submit_score()

func submit_score() -> void:
	var player_name = name_input.text.strip_edges()
	
	# If name is empty, use "Player"
	if player_name.is_empty():
		player_name = "Player"
	
	# Add score to scoreboard
	scoreboard_manager.add_score(player_name, current_final_height, current_final_score)
	
	# Show the scoreboard view
	populate_scoreboard()
	set_ui_state(UIState.SCOREBOARD_VIEW)

func populate_scoreboard() -> void:
	# Clear existing items
	for child in scoreboard_list.get_children():
		child.queue_free()
	
	# Add header
	var header = create_scoreboard_row("RANK", "NAME", "HEIGHT", "POINTS", true)
	scoreboard_list.add_child(header)
	
	# Add scores
	var scores = scoreboard_manager.high_scores
	for i in range(scores.size()):
		var score = scores[i]
		var row = create_scoreboard_row(
			str(i + 1),
			score.name,
			scoreboard_manager.format_height(score.height),
			scoreboard_manager.format_points(score.points),
			false
		)
		
		# Highlight current score
		if i < scores.size() and score.height == current_final_height and score.points == current_final_score:
			row.modulate = Color(1, 1, 0.5)  # Light yellow highlight
		
		scoreboard_list.add_child(row)

func create_scoreboard_row(rank: String, name: String, height: String, points: String, is_header: bool) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_FILL
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	
	# Create labels with larger font sizes
	var font_size = 35 if is_header else 28
	
	var rank_label = Label.new()
	rank_label.text = rank
	rank_label.custom_minimum_size = Vector2(70, 0)  # Increased width
	rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rank_label.add_theme_font_size_override("font_size", font_size)
	if is_header:
		rank_label.add_theme_color_override("font_color", Color(1, 0.8, 0.2))
	row.add_child(rank_label)
	
	var name_label = Label.new()
	name_label.text = name
	name_label.custom_minimum_size = Vector2(150, 0)  # Increased width
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.add_theme_font_size_override("font_size", font_size)
	if is_header:
		name_label.add_theme_color_override("font_color", Color(1, 0.8, 0.2))
	row.add_child(name_label)
	
	var height_label = Label.new()
	height_label.text = height
	height_label.custom_minimum_size = Vector2(150, 0)  # Increased width
	height_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	height_label.add_theme_font_size_override("font_size", font_size)
	if is_header:
		height_label.add_theme_color_override("font_color", Color(1, 0.8, 0.2))
	row.add_child(height_label)
	
	var points_label = Label.new()
	points_label.text = points
	points_label.custom_minimum_size = Vector2(150, 0)  # Increased width
	points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	points_label.add_theme_font_size_override("font_size", font_size)
	if is_header:
		points_label.add_theme_color_override("font_color", Color(1, 0.8, 0.2))
	row.add_child(points_label)
	
	return row

func set_ui_state(state: UIState) -> void:
	current_state = state
	
	match state:
		UIState.SCORE_INPUT:
			# Show name input, hide scoreboard
			$CenterContainer/PanelContainer/MarginContainer/VBoxContainer/NameInput.visible = true
			scoreboard_container.visible = false
			retry_button.visible = false
			main_menu_button.visible = false
			
		UIState.SCOREBOARD_VIEW:
			# Hide name input, show scoreboard and buttons
			$CenterContainer/PanelContainer/MarginContainer/VBoxContainer/NameInput.visible = false
			scoreboard_container.visible = true
			retry_button.visible = true
			main_menu_button.visible = true
			
			# Reset current selection to first button
			current_selection = 0
			update_selection()
