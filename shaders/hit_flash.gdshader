// hit_flash.gdshader
// Enemy sprite shader: per-zone readability (inner rim light + dark-tone
// lift) and the white hit flash. Obstacle._ready() assigns a per-instance
// ShaderMaterial with this shader to every enemy sprite that has no material.
//
// Uniforms and who drives them:
//   flash        Obstacle: 1 -> 0 over hit_flash_duration on each non-lethal
//                hit. Applied LAST, so a hit always flashes pure white (over
//                the rim and the lift too).
//   rim_color    ZoneDefinition.enemy_rim_color (SpawnManager -> Obstacle).
//   rim_strength ZoneDefinition.enemy_rim_strength; 0 = off (ground). How far
//                pixels near the silhouette edge are pushed toward rim_color.
//   rim_width_px Rim width in pixels of the SOURCE texture. Obstacle sets it
//                per instance to rim_screen_px / sprite global scale, so the
//                rim is the same width on screen for every enemy size.
//   brighten     ZoneDefinition.enemy_brighten. 0 = the original shading
//                (art colours squared: darker, more saturated; unchanged
//                look for the ground zone), 1 = the art's own colours. Lifts
//                dark tones the most; whites stay white.
//   hue_shift    Per enemy scene (Obstacle.hue_shift export), radians; 0 =
//                off (default; skipped by a uniform branch, so other enemies
//                pay nothing). Rotates the hue of the sprite's colour around
//                the grey axis (luma roughly kept), after the brighten step
//                and before the rim and the flash. A stand-in for a second
//                colour of the same art (unused since the scout saucer got
//                its own ufo_2 art).
//
// Rim: an INNER rim (inside the silhouette, so art that fills its canvas to
// the edge still gets one). A pixel is rim when any of the 4 neighbours at
// rim_width_px (+-x, +-y) is transparent: rim = own alpha * (1 - min of the
// neighbour alphas). UVs outside the sprite's region (REGION_RECT: the whole
// texture for plain sprites, the current frame for AtlasTexture frames of an
// AnimatedSprite2D) count as transparent, so canvas-edge cuts get a rim and
// sprite sheet frames never bleed into each other. Defining RIM_8_TAPS
// (#define after shader_type) adds the 4 diagonal neighbours: slightly fuller
// rims on diagonal edges for 4 more samples; off by default (barely visible
// at a 2 px rim).
//
// Order: COLOR (= texture * modulate, so modulate tints still apply) ->
// brighten -> hue_shift -> rim -> flash. Alpha is always texture alpha * modulate alpha.
//
// Cost (Mobile / GL ES 3), on top of the engine's own texture sample: both
// features sit behind uniform branches. brighten < 1: +1 sample (the original
// shader's cost; ground). rim_strength > 0: +4 samples and ~40 ALU ops.
shader_type canvas_item;

uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 rim_color : source_color = vec4(0.75, 0.95, 1.0, 1.0);
uniform float rim_strength : hint_range(0.0, 1.0) = 0.0;
uniform float rim_width_px = 10.0;
uniform float brighten : hint_range(0.0, 1.0) = 0.0;
uniform float hue_shift = 0.0;

// 1 inside the region rect (lo .. hi), 0 outside
float inside_rect(vec2 uv, vec2 lo, vec2 hi) {
	vec2 s = step(lo, uv) * step(uv, hi);
	return s.x * s.y;
}

// Texture alpha at UV + offset, 0 outside the sprite's region (a macro:
// passing TEXTURE into a function trips a shader compiler error in 4.7)
#define RIM_TAP(offset) (texture(TEXTURE, clamp(UV + (offset), lo, hi)).a * inside_rect(UV + (offset), lo, hi))

void fragment() {
	// In Godot 4 the incoming COLOR is already texture * modulate
	vec4 tex = COLOR;
	vec3 col = tex.rgb;

	// brighten 0 = the original enemy shading, reproduced exactly: this
	// shader used to multiply COLOR by the texture once more, i.e. the art's
	// colours (and edge alpha) squared, which darkens mid and dark tones a
	// lot (and suits the light ground sky). brighten 1 = the art's own
	// colours. Uniform branch: at 1 the extra sample is skipped.
	if (brighten < 1.0) {
		vec4 extra = mix(texture(TEXTURE, UV), vec4(1.0), brighten);
		col *= extra.rgb;
		tex.a *= extra.a;
	}

	// Hue rotation around the grey axis (Rodrigues); uniform branch
	if (hue_shift != 0.0) {
		vec3 k = vec3(0.57735);
		float c = cos(hue_shift);
		col = col * c + cross(k, col) * sin(hue_shift) + k * dot(k, col) * (1.0 - c);
		col = max(col, vec3(0.0));
	}

	// Skipped for 1-4 px textures (untextured Polygon2D children sharing the
	// parent's material would read every neighbour as transparent). Uniform
	// condition only, so the neighbour samples keep valid derivatives (mips).
	// The rim tints the pixel's colour; its own alpha (output) scales it.
	if (rim_strength > 0.0 && TEXTURE_PIXEL_SIZE.x < 0.25) {
		vec2 lo = REGION_RECT.xy;
		vec2 hi = REGION_RECT.xy + REGION_RECT.zw;
		vec2 d = TEXTURE_PIXEL_SIZE * rim_width_px;
		float m = RIM_TAP(vec2(d.x, 0.0));
		m = min(m, RIM_TAP(vec2(-d.x, 0.0)));
		m = min(m, RIM_TAP(vec2(0.0, d.y)));
		m = min(m, RIM_TAP(vec2(0.0, -d.y)));
#ifdef RIM_8_TAPS
		vec2 e = d * 0.7071;
		m = min(m, RIM_TAP(e));
		m = min(m, RIM_TAP(-e));
		m = min(m, RIM_TAP(vec2(e.x, -e.y)));
		m = min(m, RIM_TAP(vec2(-e.x, e.y)));
#endif
		float rim = clamp(1.0 - m, 0.0, 1.0) * rim_strength;
		col = mix(col, rim_color.rgb, rim);
	}

	COLOR = vec4(mix(col, vec3(1.0), flash), tex.a);
}
