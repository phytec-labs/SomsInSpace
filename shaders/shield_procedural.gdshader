// shield_procedural.gdshader
// Procedural shield sphere (no texture): the player's ShieldRing/Field
// ColorRect (scenes/player.tscn) when GameConfig.shield_style = Procedural.
// Everything is computed from UV (0..1 across the square quad):
//
//   p = (UV - 0.5) * 2   (quad edge at |p| = 1, sphere edge at edge_radius)
//
// - Body: faint fill_color tint inside the sphere.
// - Rim: fresnel-like rim glow from a fake sphere normal, brightening toward
//   the edge (rim_power, rim_glow).
// - Hex grid: wrapped on the sphere (cells compress toward the rim), drifting
//   slowly (hex_drift), stronger toward the rim; a soft shimmer band sweeps
//   down over it.
// - Halo: soft glow outside the edge, reaching 0 before the quad edge (keep
//   edge_radius + halo_width <= 1.0).
// - Hit ripple: an expanding ring from hit_pos (p space); player.gd sets
//   hit_pos when a hit is absorbed and advances hit_time (seconds since the
//   hit) while it plays; a large hit_time (>= ripple_duration) means none.
// - COLOR (modulate) is multiplied last, so the code-driven pulse, hit pop
//   and warning blink in player.gd apply on top. Standard alpha blending.
//
// GLES3 / Mobile safe and cheap: no texture reads, no derivatives, no loops;
// anti-aliasing uses fixed smoothstep widths (aa, in p units: ~1.2 px for the
// player's 324 px quad at the Player's 0.8 scale).
shader_type canvas_item;

// Sphere edge radius in p units (quad half-size = 1.0)
uniform float edge_radius : hint_range(0.3, 1.0) = 0.78;
// Smoothstep width of the sphere edge (p units)
uniform float aa : hint_range(0.001, 0.05) = 0.01;

// Body tint
uniform vec4 fill_color : source_color = vec4(0.15, 0.50, 1.0, 1.0);
uniform float fill_alpha : hint_range(0.0, 1.0) = 0.14;

// Rim (fresnel) glow; also the halo color. Saturated so it reads on the
// light ground / atmosphere skies, not only on space.
uniform vec4 rim_color : source_color = vec4(0.20, 0.62, 1.0, 1.0);
uniform float rim_glow : hint_range(0.0, 3.0) = 1.1;
// Higher = thinner rim
uniform float rim_power : hint_range(0.5, 8.0) = 2.5;
// Thin bright line just inside the edge
uniform vec4 edge_color : source_color = vec4(0.85, 0.97, 1.0, 1.0);
uniform float edge_width : hint_range(0.0, 0.2) = 0.035;
uniform float edge_strength : hint_range(0.0, 2.0) = 0.9;
// Soft specular spot (upper left) for the sphere read
uniform float highlight_strength : hint_range(0.0, 1.0) = 0.25;

// Outer halo (outside the edge)
uniform float halo_width : hint_range(0.0, 0.5) = 0.18;
uniform float halo_strength : hint_range(0.0, 2.0) = 0.7;

// Hex grid
uniform vec4 hex_color : source_color = vec4(0.40, 0.85, 1.0, 1.0);
// Cells across one sphere radius (at the center)
uniform float hex_scale : hint_range(1.0, 20.0) = 2.6;
// Line half-width in cell units (cell inradius = 0.5)
uniform float hex_line_width : hint_range(0.005, 0.2) = 0.03;
uniform float hex_strength : hint_range(0.0, 1.0) = 0.45;
// Grid drift (cells per second)
uniform vec2 hex_drift = vec2(0.03, -0.06);

// Shimmer band sweeping down the sphere
uniform float shimmer_speed : hint_range(0.0, 3.0) = 0.6;
uniform float shimmer_strength : hint_range(0.0, 2.0) = 0.6;

// Hit ripple
uniform vec2 hit_pos = vec2(0.0, -0.78);
uniform float hit_time = 100.0;
uniform float ripple_duration : hint_range(0.05, 2.0) = 0.5;
// Ring growth (p units per second)
uniform float ripple_speed : hint_range(0.1, 10.0) = 3.2;
uniform float ripple_width : hint_range(0.01, 0.5) = 0.15;
uniform float ripple_strength : hint_range(0.0, 3.0) = 1.5;

// Distance from a point to the nearest hex cell edge (0 on the edge, 0.5 at
// the center). Pointy-top tiling built from two offset rectangular grids.
float hex_edge_distance(vec2 q) {
	const vec2 s = vec2(1.0, 1.7320508);
	vec4 c = floor(vec4(q, q - vec2(0.5, 1.0)) / s.xyxy) + 0.5;
	vec2 a = q - c.xy * s;
	vec2 b = q - (c.zw + 0.5) * s;
	vec2 h = dot(a, a) < dot(b, b) ? a : b;
	h = abs(h);
	float hex_d = max(dot(h, vec2(0.8660254, 0.5)), h.x);
	return 0.5 - hex_d;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float rn = r / edge_radius;

	// Inside mask and fake sphere normal z (1 at the center, 0 at the edge)
	float inside = 1.0 - smoothstep(edge_radius - aa, edge_radius + aa, r);
	float z = sqrt(max(1.0 - min(rn * rn, 1.0), 0.0));
	float fres = 1.0 - z;

	// Rim: fresnel glow inside, brightest at the edge, plus a thin edge line
	float rim = pow(fres, rim_power) * rim_glow * inside;
	float edge = smoothstep(edge_radius - edge_width, edge_radius - aa, r) * inside * edge_strength;
	vec2 hl = p - vec2(-0.4, -0.45) * edge_radius;
	float spec = 1.0 - smoothstep(0.0, 0.38 * edge_radius, length(hl));
	spec = spec * spec * highlight_strength * inside;

	// Halo: squared falloff outside the edge, 0 at edge_radius + halo_width
	float ho = clamp((r - edge_radius) / max(halo_width, 0.001), 0.0, 1.0);
	float halo = (1.0 - ho) * (1.0 - ho) * halo_strength * (1.0 - inside);

	// Hex grid on the sphere: lens projection compresses cells at the rim
	vec2 q = p / (edge_radius * (0.35 + 0.65 * z));
	q = q * hex_scale + hex_drift * TIME;
	float e = hex_edge_distance(q);
	float line = 1.0 - smoothstep(hex_line_width, hex_line_width * 2.0, e);

	// Shimmer: a soft horizontal band sweeping from top to bottom
	float band_y = mod(TIME * shimmer_speed, 3.0) - 1.5;
	float shimmer = 1.0 - smoothstep(0.0, 0.3, abs(p.y - band_y));
	shimmer *= shimmer_strength;

	// Hit ripple: expanding ring from hit_pos plus a flash at the impact,
	// fading over ripple_duration
	float active = step(hit_time, ripple_duration);
	float rt = clamp(hit_time / ripple_duration, 0.0, 1.0);
	float hd = distance(p, hit_pos);
	float ring = 1.0 - smoothstep(0.0, ripple_width, abs(hd - hit_time * ripple_speed));
	float fade = 1.0 - rt;
	float impact = (1.0 - smoothstep(0.0, 0.2, hd)) * 0.5 * fade * fade;
	float ripple = (ring * fade + impact) * ripple_strength * active;
	ripple *= max(inside, halo);

	// Hex lines: faint at the center, stronger toward the rim, lit by the
	// shimmer and the ripple
	float hex = line * inside * hex_strength * (0.35 + 0.65 * fres + shimmer + 2.0 * ripple);

	// Compose (weighted colors, summed alpha)
	float a_fill = fill_alpha * inside * (1.0 + 0.5 * shimmer);
	float a_rim = rim + halo;
	float a_white = ripple + spec + edge;
	float a_sum = a_fill + a_rim + hex + a_white;
	vec3 rgb = (fill_color.rgb * a_fill + rim_color.rgb * a_rim + hex_color.rgb * hex
		+ edge_color.rgb * a_white) / max(a_sum, 0.0001);
	COLOR = vec4(rgb, clamp(a_sum, 0.0, 1.0)) * COLOR;
}
