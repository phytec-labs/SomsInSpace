// ufo_beam.gdshader
// Procedural tractor beam (no texture): the UFO's Beam/Field ColorRect
// (scenes/obstacles/ufo_obstacle.tscn). Everything is computed from UV
// (0..1 across the quad); UV (0.5, 0) is the saucer's emitter, v runs down
// the beam:
//
//   x = UV.x - 0.5   (quad edge at |x| = 0.5)
//
// - Cone: half-width grows linearly from top_half_width (v = 0) to
//   bottom_half_width (v = 1), in fractions of the quad width; soft sides
//   (edge_softness, relative to the local half-width) and a brighter core
//   along the center line (core_strength). The sides are half faded at the
//   nominal half-width (matching the BeamArea polygon) and fully faded at
//   half-width * (1 + 0.5 * edge_softness); keep
//   bottom_half_width * (1 + 0.5 * edge_softness) < 0.5 so they fade out
//   inside the quad.
// - Falloff: bright at the emitter, pow(1 - v, fade_power) down the beam;
//   the last end_fade of the quad fades fully to 0 (no hard end), and the
//   first ~3% fades in (that part sits behind the hull anyway); the first
//   ~12% is brighter (emitter_glow).
// - Rings: bands around the cone scrolling UP toward the saucer (the pull
//   direction), bowed downward in the middle like the front half of a ring
//   around a cone (ring_curve).
// - Shimmer: a slow sideways wobble of the cone plus two drifting sine bands
//   (shimmer_strength).
// - capture (0..1, ufo_obstacle.gd raises it while the player is inside the
//   beam): brightens the core and the rings and fades in a second, denser,
//   faster ring set, so being caught reads clearly. A second layer instead
//   of scaling the ring speed: scaling TIME * speed by a changing value
//   would make the rings jump.
// - COLOR (modulate) is multiplied last, so the code-driven fade in/out and
//   alpha pulse in ufo_obstacle.gd apply on top. Standard alpha blending.
//
// GLES3 / Mobile safe and cheap: no texture reads, no derivatives, no loops;
// ~10 sin/fract/smoothstep groups per fragment.
shader_type canvas_item;

// Cone half-width at the emitter / at the bottom of the quad (fractions of
// the quad width)
uniform float top_half_width : hint_range(0.0, 0.5) = 0.2;
uniform float bottom_half_width : hint_range(0.0, 0.5) = 0.4;
// Side softness, relative to the local half-width (0 = hard edge)
uniform float edge_softness : hint_range(0.0, 1.0) = 0.45;

// Vertical falloff: higher = fades faster below the emitter
uniform float fade_power : hint_range(0.1, 4.0) = 0.9;
// Fraction of the quad (at the bottom) over which the beam fades to 0
uniform float end_fade : hint_range(0.01, 0.5) = 0.15;
// Extra brightness right under the emitter
uniform float emitter_glow : hint_range(0.0, 3.0) = 0.8;

// Colors and base opacity
uniform vec4 beam_color : source_color = vec4(0.85, 0.35, 1.0, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 0.85, 0.97, 1.0);
uniform float beam_alpha : hint_range(0.0, 1.0) = 0.35;
// Extra brightness / opacity along the center line
uniform float core_strength : hint_range(0.0, 2.0) = 0.6;

// Rings scrolling up toward the saucer
uniform float ring_count : hint_range(1.0, 20.0) = 6.0;
// Rings per second
uniform float ring_speed : hint_range(0.0, 4.0) = 0.9;
// Ring half-width in ring periods (0..0.5)
uniform float ring_width : hint_range(0.01, 0.5) = 0.14;
uniform float ring_strength : hint_range(0.0, 2.0) = 0.55;
// How far the ring middle bows down (in half-widths' worth of v)
uniform float ring_curve : hint_range(0.0, 1.0) = 0.35;

// Sideways wobble + drifting bands
uniform float shimmer_strength : hint_range(0.0, 1.0) = 0.3;

// 0 = idle, 1 = the player is caught (driven by ufo_obstacle.gd)
uniform float capture : hint_range(0.0, 1.0) = 0.0;

// Soft band of half-width w around the middle of each period of `phase`
float ring_band(float phase, float w) {
	float d = abs(fract(phase) - 0.5);
	return 1.0 - smoothstep(w * 0.4, w, d);
}

void fragment() {
	float v = UV.y;
	float t = TIME;

	// Sideways wobble, growing down the beam
	float wobble = shimmer_strength * 0.03 * v * sin(v * 7.0 - t * 1.6);
	float x = UV.x - 0.5 - wobble;

	// Cone mask with soft sides
	float hw = mix(top_half_width, bottom_half_width, v);
	float xn = abs(x) / max(hw, 0.001);
	float cone = 1.0 - smoothstep(1.0 - 0.5 * edge_softness, 1.0 + 0.5 * edge_softness, xn);

	// Core: bright center line, also used for the ring curvature
	float across = clamp(1.0 - xn * xn, 0.0, 1.0);
	float core = across * across * core_strength * (1.0 + 1.2 * capture);

	// Vertical falloff, soft start and soft end
	float fall = pow(max(1.0 - v, 0.0), fade_power);
	fall *= smoothstep(0.0, 0.03, v);
	fall *= 1.0 - smoothstep(1.0 - end_fade, 1.0, v);
	// Keep some body down the beam (pow alone gets too thin before the end)
	fall = max(fall, 0.35 * (1.0 - smoothstep(1.0 - end_fade, 1.0, v)) * smoothstep(0.0, 0.03, v));
	// Emitter glow: the first ~12% is brighter, tying the beam to the
	// saucer's glowing emitter
	fall *= 1.0 + emitter_glow * (1.0 - smoothstep(0.0, 0.12, v));

	// Rings: s bows down in the middle (front half of a ring around the cone)
	float s = v + ring_curve * hw * sqrt(across);
	float rings = ring_band(s * ring_count + t * ring_speed, ring_width);
	rings *= ring_strength * (1.0 + 0.8 * capture);
	// Capture: a denser, faster ring set fades in
	float rings2 = ring_band(s * ring_count * 1.7 + t * ring_speed * 2.6, ring_width * 0.8);
	rings += rings2 * ring_strength * capture;
	// Rings are strongest across the middle of the cone, fading at the sides
	rings *= 0.4 + 0.6 * across;

	// Shimmer: two slow sine bands drifting along the beam
	float bands = 0.5 * sin(v * 9.0 + t * 2.1 + x * 6.0) + 0.5 * sin(v * 17.0 - t * 1.3);
	float shimmer = 1.0 + shimmer_strength * 0.5 * bands;

	// Compose (weighted colors, summed alpha)
	float body = beam_alpha * shimmer * (1.0 + 0.5 * capture);
	float a_body = body;
	float a_core = beam_alpha * core;
	float a_ring = beam_alpha * rings;
	float a_sum = (a_body + a_core + a_ring) * cone * fall;
	vec3 rgb = (beam_color.rgb * a_body + core_color.rgb * (a_core + 0.6 * a_ring)
		+ beam_color.rgb * 0.4 * a_ring) / max(a_body + a_core + a_ring, 0.0001);
	COLOR = vec4(rgb, clamp(a_sum, 0.0, 1.0)) * COLOR;
}
