# ship_select_ui.gd
# "Choose your SoM" screen, shown by main_menu.gd before a run. One card per
# ship in GameConfig.ships (tap to select), a large tinted preview, name,
# tagline and stat bars, plus LAUNCH / BACK.
#
# Input: tap a card or ui_left / ui_right to change ship; LAUNCH / BACK via
# touch, click or ui_up / ui_down + ui_accept (MenuButtonGroup); ui_cancel =
# BACK. Returns to the main menu after IDLE_TIMEOUT_SECONDS without input.
extends CenterContainer

signal launch_requested(index: int)
signal back_requested

# Preloaded (rather than relying on the global class_name cache) so the
# script resolves even when .godot/ has not been regenerated.
const MenuButtonGroupScript := preload("res://scripts/ui/menu_button_group.gd")
const IdleReturnScript := preload("res://scripts/ui/idle_return.gd")

## Kiosk: back to the main menu list after this long without input.
const IDLE_TIMEOUT_SECONDS := 30.0

const CARD_SIZE := Vector2(196, 170)
const CARD_PREVIEW_HEIGHT := 90.0
const CARD_FONT_SIZE := 22
const CARD_NAME_COLOR := Color(1, 1, 1)
const CARD_SELECTED_NAME_COLOR := Color(1, 1, 0)
## The Player scene's Ship sprite scale (ShipDefinition.visual_offset_y is in
## Player-local px at this scale)
const SHIP_SPRITE_SCALE := 0.125

@onready var preview: TextureRect = $PanelContainer/MarginContainer/VBoxContainer/Preview
@onready var name_label: Label = $PanelContainer/MarginContainer/VBoxContainer/NameLabel
@onready var tagline_label: Label = $PanelContainer/MarginContainer/VBoxContainer/TaglineLabel
@onready var description_label: Label = $PanelContainer/MarginContainer/VBoxContainer/DescriptionLabel
@onready var health_bar: ProgressBar = $PanelContainer/MarginContainer/VBoxContainer/Stats/HealthBar
@onready var speed_bar: ProgressBar = $PanelContainer/MarginContainer/VBoxContainer/Stats/SpeedBar
@onready var fire_rate_bar: ProgressBar = $PanelContainer/MarginContainer/VBoxContainer/Stats/FireRateBar
@onready var cards_container: HBoxContainer = $PanelContainer/MarginContainer/VBoxContainer/Cards
@onready var launch_button: Button = $PanelContainer/MarginContainer/VBoxContainer/LaunchButton
@onready var back_button: Button = $PanelContainer/MarginContainer/VBoxContainer/BackButton

var ships: Array = []
var selected_index: int = 0
var cards: Array[Button] = []
var menu_group: MenuButtonGroupScript
var idle_return: IdleReturnScript

# Stat maxima across all ships (stat bars are relative to the best ship)
var _max_health: float = 1.0
var _max_speed: float = 1.0
var _max_fire_rate: float = 1.0

var _card_style: StyleBox
var _card_selected_style: StyleBox


func _ready() -> void:
	ships = GameSession.get_ships()
	for ship in ships:
		_max_health = maxf(_max_health, ship.max_health)
		_max_speed = maxf(_max_speed, ship.speed)
		_max_fire_rate = maxf(_max_fire_rate, ship.get_fire_rate_factor())

	_card_style = launch_button.get_theme_stylebox("normal")
	_card_selected_style = launch_button.get_theme_stylebox("hover")
	_build_cards()

	# LAUNCH / BACK. Touch activates on release so the rest of the gesture
	# can't leak into the level or the main menu list shown next.
	menu_group = MenuButtonGroupScript.new()
	menu_group.name = "MenuButtonGroup"
	menu_group.activate_touch_on_release = true
	add_child(menu_group)
	menu_group.setup([launch_button, back_button], false)
	menu_group.button_activated.connect(_on_button_activated)

	visibility_changed.connect(_on_visibility_changed)

	# Kiosk idle timeout (added last so its _input runs before siblings')
	idle_return = IdleReturnScript.new()
	idle_return.timeout_seconds = IDLE_TIMEOUT_SECONDS
	add_child(idle_return)
	idle_return.idle_timeout.connect(_on_back)

	select_ship(GameSession.selected_ship_index)


## Show the screen with the session's current ship selected.
func open() -> void:
	select_ship(GameSession.selected_ship_index)
	show()


func select_ship(index: int) -> void:
	if ships.is_empty():
		return
	selected_index = posmod(index, ships.size())
	var ship = ships[selected_index]

	_show_ship(preview, ship)
	name_label.text = ship.display_name
	tagline_label.text = ship.tagline
	description_label.text = ship.description
	description_label.visible = not ship.description.is_empty()
	health_bar.value = ship.max_health / _max_health
	speed_bar.value = ship.speed / _max_speed
	fire_rate_bar.value = ship.get_fire_rate_factor() / _max_fire_rate

	for i in cards.size():
		_style_card(cards[i], i == selected_index)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	# ui_accept / ui_up / ui_down are handled by the MenuButtonGroup
	if event.is_action_pressed("ui_left"):
		select_ship(selected_index - 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		select_ship(selected_index + 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back()
	elif event is InputEventScreenTouch and event.pressed:
		# Cards are hit-tested here like MenuButtonGroup's buttons, so a tap
		# selects even if the emulated mouse click is lost; the click's
		# Button.pressed then just re-selects the same card.
		for i in cards.size():
			if cards[i].get_global_rect().has_point(event.position):
				select_ship(i)
				get_viewport().set_input_as_handled()
				return


func _build_cards() -> void:
	for child in cards_container.get_children():
		cards_container.remove_child(child)
		child.queue_free()
	cards.clear()

	for i in ships.size():
		var ship = ships[i]
		var card := Button.new()
		card.name = "Card%d" % (i + 1)
		card.custom_minimum_size = CARD_SIZE
		card.focus_mode = Control.FOCUS_NONE
		card.add_theme_stylebox_override("hover", _card_selected_style)
		card.add_theme_stylebox_override("pressed", _card_selected_style)
		card.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

		var box := VBoxContainer.new()
		box.name = "Content"
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
		box.add_theme_constant_override("separation", 4)
		card.add_child(box)

		# Tinted ship thumbnail (doubles as the tint swatch)
		var thumb := TextureRect.new()
		thumb.name = "Thumb"
		thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		thumb.custom_minimum_size = Vector2(0, CARD_PREVIEW_HEIGHT)
		thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		box.add_child(thumb)
		_show_ship(thumb, ship)

		var label := Label.new()
		label.name = "NameLabel"
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.text = ship.display_name
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", CARD_FONT_SIZE)
		box.add_child(label)

		card.pressed.connect(_on_card_pressed.bind(i))
		cards_container.add_child(card)
		cards.append(card)


# Ship art in `holder` (the Preview or a card's Thumb, sized by its container)
# at the same relative size and center as in the game: the definition's
# visual_scale / visual_offset_y (Player-local px at the Ship sprite scale
# SHIP_SPRITE_SCALE) are applied here, so all ships show the same visible
# height. The holder draws nothing itself; a child TextureRect "Ship" (keep
# aspect, centered) is laid out by _layout_ship_view() whenever the holder
# resizes.
func _show_ship(holder: TextureRect, ship) -> void:
	holder.texture = null
	var view := holder.get_node_or_null("Ship") as TextureRect
	if view == null:
		view = TextureRect.new()
		view.name = "Ship"
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		holder.add_child(view)
		holder.resized.connect(_layout_ship_view.bind(holder))
	view.texture = ship.texture
	view.self_modulate = ship.tint
	holder.set_meta(&"ship_visual", Vector2(ship.visual_scale, ship.visual_offset_y))
	_layout_ship_view(holder)


# The view is the holder's rect scaled by visual_scale around its center (the
# texture fit scales with it), shifted down by visual_offset_y converted from
# Player-local px to holder px (/ SHIP_SPRITE_SCALE = texture px, x the
# holder's texture fit)
func _layout_ship_view(holder: TextureRect) -> void:
	var view := holder.get_node_or_null("Ship") as TextureRect
	if view == null or view.texture == null:
		return
	var visual: Vector2 = holder.get_meta(&"ship_visual", Vector2(1.0, 0.0))
	var tex_size := view.texture.get_size()
	var fit := minf(holder.size.x / tex_size.x, holder.size.y / tex_size.y)
	view.size = holder.size * visual.x
	view.position = (holder.size - view.size) / 2.0 \
		+ Vector2(0.0, visual.y / SHIP_SPRITE_SCALE * fit)


func _style_card(card: Button, selected: bool) -> void:
	card.add_theme_stylebox_override("normal", _card_selected_style if selected else _card_style)
	var label := card.get_node_or_null("Content/NameLabel") as Label
	if label:
		label.add_theme_color_override("font_color", CARD_SELECTED_NAME_COLOR if selected else CARD_NAME_COLOR)


func _on_card_pressed(index: int) -> void:
	select_ship(index)


func _on_button_activated(_index: int, button: Button) -> void:
	if button == launch_button:
		launch_requested.emit(selected_index)
	else:
		_on_back()


func _on_back() -> void:
	back_requested.emit()


func _on_visibility_changed() -> void:
	if visible:
		# LAUNCH highlighted by default, so ui_accept launches
		menu_group.select(0)
