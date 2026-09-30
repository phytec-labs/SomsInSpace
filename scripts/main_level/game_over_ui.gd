# game_over_ui.gd
extends Control

signal retry_pressed
signal main_menu_pressed

@onready var header_label: Label = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/GameOverLabel
@onready var bonus_label: Label = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ScoreContainer/BonusLabel
@onready var height_label = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ScoreContainer/HeightLabel
@onready var score_label = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ScoreContainer/ScoreLabel
@onready var retry_button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ButtonContainer/RetryButton
@onready var main_menu_button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ButtonContainer/MainMenuButton

# New UI components
@onready var name_input = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/NameInput/LineEdit
@onready var submit_button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/NameInput/SubmitButton
@onready var scoreboard_container = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ScoreboardContainer
@onready var scoreboard_list = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ScoreboardContainer/ScoreboardList

# Preloaded (rather than relying on the global class_name cache) so the
# script resolves even when .godot/ has not been regenerated.
const MenuButtonGroupScript := preload("res://scripts/ui/menu_button_group.gd")
const IdleReturnScript := preload("res://scripts/ui/idle_return.gd")

## Kiosk: return to the main menu after this long without input.
const IDLE_TIMEOUT_SECONDS := 60.0

var menu_group: MenuButtonGroupScript
var idle_return: IdleReturnScript
var current_final_height: float = 0
var current_final_score: int = 0
var scoreboard_manager = null
var is_victory: bool = false

const GAME_OVER_TEXT := "Game Over"
const VICTORY_TEXT := "ORBIT REACHED!"
const VICTORY_COLOR := Color(1, 0.8, 0.2)

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
	
	# Button navigation/highlight/touch. Only active in SCOREBOARD_VIEW
	# (see set_ui_state); also accepts the move_up/move_down actions.
	menu_group = MenuButtonGroupScript.new()
	menu_group.name = "MenuButtonGroup"
	menu_group.use_move_actions = true
	# Touch activates on release (inside the same button) so one tap fires
	# exactly once and the rest of the gesture can't leak into the next scene.
	menu_group.activate_touch_on_release = true
	menu_group.enabled = false
	add_child(menu_group)
	menu_group.setup([retry_button, main_menu_button])
	menu_group.button_activated.connect(_on_button_activated)
	
	# Connect submit button
	submit_button.pressed.connect(_on_submit_button_pressed)
	
	# Connect name input events to handle Enter key
	name_input.text_submitted.connect(_on_name_submitted)
	
	# Connect visibility signal
	visibility_changed.connect(_on_visibility_changed)

	# Kiosk idle timeout. Added last so its _input sees every event (touch,
	# onscreen keyboard taps, keys) before siblings can consume it.
	idle_return = IdleReturnScript.new()
	idle_return.timeout_seconds = IDLE_TIMEOUT_SECONDS
	add_child(idle_return)
	idle_return.idle_timeout.connect(_on_idle_timeout)
	
	# Initially hide the scoreboard
	set_ui_state(UIState.SCORE_INPUT)
	
	# Initially hide the screen
	hide()

func _input(event: InputEvent) -> void:
	if not visible:
		return

	# Handle touch input for the NameInput state
	if current_state == UIState.SCORE_INPUT and event is InputEventScreenTouch and event.pressed:
		# Check if the LineEdit was touched
		if name_input.get_global_rect().has_point(event.position):
			name_input.grab_focus()
			get_viewport().set_input_as_handled()
			return

	# Button navigation in SCOREBOARD_VIEW is handled by menu_group

# Victory mode: gold "ORBIT REACHED!" header plus the bonus line. Reset to
# game-over mode automatically whenever the screen is hidden.
func set_victory(victory: bool, bonus: int = 0) -> void:
	is_victory = victory
	if victory:
		header_label.text = VICTORY_TEXT
		header_label.add_theme_color_override("font_color", VICTORY_COLOR)
		bonus_label.text = "Victory bonus: +%d" % bonus
		bonus_label.visible = true
	else:
		header_label.text = GAME_OVER_TEXT
		header_label.remove_theme_color_override("font_color")
		bonus_label.visible = false

func set_final_height(height: float) -> void:
	current_final_height = height
	if height_label:
		height_label.text = scoreboard_manager.format_height(height)

func set_final_score(score: int) -> void:
	current_final_score = score
	if score_label:
		score_label.text = scoreboard_manager.format_points(score)

func _on_button_activated(_index: int, button: Button) -> void:
	match button:
		retry_button:
			retry_pressed.emit()
		main_menu_button:
			main_menu_pressed.emit()

# Nobody touched the results screen: go back to the attract/main menu. An
# unsubmitted name entry is abandoned (no score is saved).
func _on_idle_timeout() -> void:
	if name_input and name_input.has_focus():
		name_input.release_focus()
	main_menu_pressed.emit()

func _on_visibility_changed() -> void:
	if not visible:
		set_victory(false)
		return
	if visible:
		# Reset UI state
		if name_input:
			name_input.text = ""  # Clear any previous text
			
		# Check if the score would make it to the leaderboard
		var would_make_leaderboard = scoreboard_manager.would_make_leaderboard(current_final_height, current_final_score)
		
		# If the score would make the leaderboard, show name input
		if would_make_leaderboard:
			set_ui_state(UIState.SCORE_INPUT)
			# Focus on the name input field - this will also trigger the keyboard to show
			# if auto_show is enabled
			if name_input:
				call_deferred("_focus_name_input")
		else:
			# Score wouldn't make leaderboard, skip name input and show scoreboard
			populate_scoreboard()
			set_ui_state(UIState.SCOREBOARD_VIEW)

# This is called deferred to ensure the UI is properly visible before setting focus
func _focus_name_input():
	name_input.grab_focus()

func _on_submit_button_pressed() -> void:
	submit_score()

func _on_name_submitted(_text: String) -> void:
	submit_score()

func submit_score() -> void:
	# Make sure we have actual text
	var player_name = name_input.text.strip_edges()
	
	# If name is empty, use "Player"
	if player_name.is_empty():
		player_name = "Player"
	
	# Release focus to hide keyboard
	name_input.release_focus()
	
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
	# Keyboard/touch/hover navigation only in the scoreboard view
	menu_group.enabled = state == UIState.SCOREBOARD_VIEW
	
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
			
			# Make sure keyboard is hidden (by removing focus)
			if name_input and name_input.has_focus():
				name_input.release_focus()
			
			# Reset current selection to first button
			menu_group.select(0)
