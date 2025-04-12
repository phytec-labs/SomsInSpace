# weapon_upgrade_collectible.gd
extends EnergyCollectible
class_name WeaponUpgradeCollectible

# Middle position variables
var stop_in_middle: bool = true
var target_y_position: float = 0
var reached_middle: bool = false
var hover_amplitude: float = 10.0
var hover_speed: float = 1.5
var hover_time: float = 0.0
var original_x: float = 0

func _ready() -> void:
	super._ready()
	# Distinctive appearance for weapon upgrade
	if sprite:
		sprite.modulate = Color(1, 0.5, 0.9) # Pink/purple color for weapon upgrade
	
	# Calculate middle position of the screen
	var viewport_size = get_viewport_rect().size
	target_y_position = viewport_size.y * 0.4  # 40% from the top
	
	# Set movement properties
	speed_multiplier = 0.7  # Slower than normal collectibles
	
	# Add a pulsating animation
	var tween = create_tween()
	tween.set_loops()  # Infinite loops
	tween.tween_property(self, "scale", Vector2(1.2, 1.2), 0.5)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.5)
	
	# Override the default energy value and points
	energy_value = 25.0  # Gives a health boost too
	points = 10  # More points than regular collectible

func _process(delta: float) -> void:
	if not is_active:
		return

	hover_time += delta
		
	if stop_in_middle and not reached_middle:
		if position.y < target_y_position:
			# Still moving toward middle position
			position.y += fall_speed * delta
			
			# Check if we've reached the middle
			if position.y >= target_y_position:
				reached_middle = true
				original_x = position.x
		else:
			reached_middle = true
			original_x = position.x
	
	if reached_middle:
		# Hover in place with a slight side-to-side movement
		position.y = target_y_position + sin(hover_time * hover_speed) * hover_amplitude * 0.5
		position.x = original_x + sin(hover_time * hover_speed * 0.7) * hover_amplitude
	else:
		# Normal behavior for movement to the middle
		super._process(delta)

# Override the handle_player_collision method
func handle_player_collision() -> void:
	# Call the normal collectible handling first (for sounds, etc)
	super.handle_player_collision()
	
	# Find the player and apply the weapon upgrade
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("upgrade_weapon"):
		player.upgrade_weapon()
	
	# Update HUD
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("update_weapon"):
		hud.update_weapon("upgraded")
	
	# Show an upgrade message
	var level = get_tree().get_first_node_in_group("level")
	if level and level.has_method("show_message"):
		level.show_message("Weapon Upgraded!")
