# entry_path.gd
# A reusable flight path for wave formations (see docs/WAVE_DESIGN.md).
# The curve is authored in normalized screen coordinates: x 0..1 of the
# viewport width, y 0..1 of its height (negative y = above the screen, x < 0
# or > 1 = beyond the sides). FormationManager scales it to pixels, mirrors it
# about the screen center for right-hand variants, and moves the formation's
# center along it by distance; members keep their formation offsets.
# Library: res://data/paths/<id>.tres (a WaveGroup names its path by id).
class_name EntryPath
extends Resource

## What the formation does once it reaches the end of the curve.
enum EndMode {
	DESCEND,            ## Keep falling straight down at descend_speed
	HOLD_THEN_DESCEND,  ## Hover (gentle x sway) for hold_seconds, then descend
	EXIT,               ## Keep flying along the last tangent until off screen
}

@export var id: StringName = &""
## Points in normalized screen coordinates (see above).
@export var curve: Curve2D
## Speed (px/s) along the curve; WaveGroup.path_speed overrides it when > 0.
@export var default_speed: float = 260.0
@export var end_mode: EndMode = EndMode.DESCEND
## HOLD_THEN_DESCEND: seconds to hover and the sway amplitude (px) while hovering.
@export var hold_seconds: float = 0.0
@export var hold_sway_amplitude: float = 0.0
## Speed (px/s) of the straight descent after the curve / hold.
@export var descend_speed: float = 180.0

# First point in normalized coordinates (0,0 if the curve is empty)
func get_start_point() -> Vector2:
	if curve == null or curve.point_count == 0:
		return Vector2(0.5, -0.1)
	return curve.get_point_position(0)

# The curve scaled to `size` pixels, optionally mirrored about the vertical
# center line (x -> width - x). A new Curve2D; callers cache it.
func build_pixel_curve(size: Vector2, mirrored: bool) -> Curve2D:
	var out := Curve2D.new()
	if curve == null:
		return out
	var flip := Vector2(-1.0 if mirrored else 1.0, 1.0)
	for i in curve.point_count:
		var p := curve.get_point_position(i)
		if mirrored:
			p.x = 1.0 - p.x
		out.add_point(p * size,
			curve.get_point_in(i) * size * flip,
			curve.get_point_out(i) * size * flip)
	return out
