# explosion.gd
# Pooled via the ObjectPool autoload: released back to the pool when the
# lifetime timer expires. Instances created directly with instantiate() are
# released into the pool the same way.
extends Node2D

# Node references
@onready var core_particles: CPUParticles2D = $CoreParticles
@onready var debris_particles: CPUParticles2D = $DebrisParticles
@onready var lifetime_timer: Timer = $LifetimeTimer

# Configuration for different explosion types
var explosion_configs = {
	0: { # SMALL
		"core_scale": 0.5,
		"core_amount": 1,
		"debris_scale": 1.5,
		"debris_amount": 10,
		"lifetime": 1.0
	},
	1: { # MEDIUM
		"core_scale": 1.0,
		"core_amount": 1,
		"debris_scale": 2.5,
		"debris_amount": 20,
		"lifetime": 1.0
	},
	2: { # LARGE
		"core_scale": 2.0,
		"core_amount": 1,
		"debris_scale": 3.5,
		"debris_amount": 30,
		"lifetime": 1.2
	},
	3: { # ENERGY
		"core_scale": 0.8,
		"core_amount": 1,
		"debris_scale": 2.0,
		"debris_amount": 15,
		"lifetime": 0.8,
		"core_color": Color(0.2, 0.4, 1.0),
		"debris_color": Color(0.5, 0.7, 1.0)
	}
}

var current_type: int = 1  # Default to medium explosion

# Scene-configured color ramps, restored before applying a type so reused
# instances don't keep a previous type's custom colors
var _default_core_ramp: Gradient
var _default_debris_ramp: Gradient

func _ready() -> void:
	_default_core_ramp = core_particles.color_ramp
	_default_debris_ramp = debris_particles.color_ramp

	# Connect timer signal
	lifetime_timer.timeout.connect(_on_lifetime_timer_timeout)

	# Set to not emitting initially
	reset()

# Set explosion type and configure accordingly
func set_explosion_type(type: int) -> void:
	current_type = type

	var config = explosion_configs[current_type]

	# Configure core particles
	core_particles.amount = config.core_amount
	core_particles.scale_amount_min = config.core_scale * 0.7
	core_particles.scale_amount_max = config.core_scale * 1.3

	# Configure debris particles
	debris_particles.amount = config.debris_amount
	debris_particles.scale_amount_min = config.debris_scale * 0.7
	debris_particles.scale_amount_max = config.debris_scale * 1.3

	# Restore default colors, then set custom colors if defined
	core_particles.color_ramp = _default_core_ramp
	debris_particles.color_ramp = _default_debris_ramp

	if config.has("core_color") and _default_core_ramp:
		var gradient = core_particles.color_ramp.duplicate()
		var colors = gradient.colors
		colors[0] = config.core_color
		gradient.colors = colors
		core_particles.color_ramp = gradient

	if config.has("debris_color") and _default_debris_ramp:
		var gradient = debris_particles.color_ramp.duplicate()
		var colors = gradient.colors
		colors[0] = config.debris_color
		gradient.colors = colors
		debris_particles.color_ramp = gradient

	# Set lifetime
	lifetime_timer.wait_time = config.lifetime

# Start the explosion
func start() -> void:
	show()
	# restart() clears any particles left over from a previous use
	core_particles.restart()
	core_particles.emitting = true
	debris_particles.restart()
	debris_particles.emitting = true
	lifetime_timer.start()

	# Optionally add camera shake or other effects here

# Reset to initial state
func reset() -> void:
	core_particles.emitting = false
	debris_particles.emitting = false
	lifetime_timer.stop()

# Timer finished - explosion is complete
func _on_lifetime_timer_timeout() -> void:
	reset()
	ObjectPool.release(self)
