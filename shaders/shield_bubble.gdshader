// shield_bubble.gdshader
// Shield sphere look for sprites/shield_dome_1.png (634x634: the full hex
// sphere, 512 px, centered with a 61 px transparent margin for the glow).
// Used per instance by the player's ShieldRing/Dome (scenes/player.tscn) and
// the shield pickup icon (scenes/collectibles/shield_pickup.tscn).
//
// - Interior: the texture's alpha is multiplied by interior_strength, so the
//   hex pattern reads subtler; it ramps back to full strength at the rim.
// - Rim: a rim_color ring over the sphere's edge band (rim_inner..rim_outer,
//   radii in UV units from sphere_center), with a thin falloff inward and a
//   soft halo fading out over the margin (glow_width).
// - COLOR (modulate) is multiplied last, so the code-driven pulse, hit pop
//   and warning blink in player.gd keep working.
//
// Edge radii measured from the padded texture (radial alpha profile): the
// drawn rim sits at ~0.36-0.37, alpha drops to 0 between 0.375 and 0.385.
//
// Kept trivial for the Mobile / GL ES renderer: one texture sample, one
// distance, a few smoothsteps and mixes.
shader_type canvas_item;

// Alpha multiplier inside the sphere (1.0 = texture as drawn)
uniform float interior_strength : hint_range(0.0, 1.0) = 0.55;
uniform vec4 rim_color : source_color = vec4(0.78, 0.96, 1.0, 1.0);
// Rim + halo intensity (0 = texture only)
uniform float rim_glow : hint_range(0.0, 2.0) = 1.0;
// Sphere edge band in UV units, measured from sphere_center
uniform float rim_inner : hint_range(0.0, 0.5) = 0.355;
uniform float rim_outer : hint_range(0.0, 0.5) = 0.378;
// Halo falloff outside rim_outer (UV units); the inward falloff is 35% of it
uniform float glow_width : hint_range(0.001, 0.2) = 0.09;
// The sphere's center in the texture (slightly off the canvas center)
uniform vec2 sphere_center = vec2(0.498, 0.494);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float d = distance(UV, sphere_center);

	// Faded interior, full strength from the rim band outward
	tex.a *= mix(interior_strength, 1.0, smoothstep(rim_inner - glow_width, rim_inner, d));

	// Ring: thin rise inside the band, soft (squared) halo fade outside
	float ring_in = smoothstep(rim_inner - glow_width * 0.35, rim_inner, d);
	float halo = 1.0 - smoothstep(rim_outer, rim_outer + glow_width, d);
	float glow = clamp(ring_in * halo * halo * rim_glow * rim_color.a, 0.0, 1.0);

	// Rim color over the texture (non-premultiplied "over")
	float a = tex.a + glow * (1.0 - tex.a);
	vec3 rgb = mix(tex.rgb * tex.a, rim_color.rgb, glow) / max(a, 0.001);
	COLOR = vec4(rgb, a) * COLOR;
}
