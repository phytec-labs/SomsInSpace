# engine_particle.gd
extends GPUParticles2D

@export var frames: SpriteFrames
var current_frame: int = 0
var frame_time: float = 0.0
var frame_duration: float = 1.0 / 12.0  # 12 FPS animation

func _ready() -> void:
	# Ensure we have frames to work with
	if not frames:
		frames = load("res://particles/explosion1.tres")
	
	# Set initial texture
	texture = frames.get_frame("default", 0)

func _process(delta: float) -> void:
	if not emitting:
		return
		
	frame_time += delta
	if frame_time >= frame_duration:
		frame_time = 0.0
		current_frame = (current_frame + 1) % frames.get_frame_count("default")
		texture = frames.get_frame("default", current_frame)
