// hit_flash.gdshader
// White hit flash for enemy sprites. Obstacle._ready() assigns a per-instance
// ShaderMaterial with this shader to every enemy sprite that has no material
// and drives `flash` 1 -> 0 over Obstacle.hit_flash_duration on each
// non-lethal hit.
//
// flash = 0 is the default canvas_item output (texture * COLOR, so modulate /
// self_modulate tints still apply). The mix toward white happens AFTER the
// tint, so tinted placeholder sprites (blimp dark red, UFO purple, drone cyan)
// flash white instead of their flat tint color. Alpha always keeps the
// texture's alpha times the modulate alpha.
//
// Kept trivial for the Mobile / GL ES renderer: one texture sample, one mix,
// one multiply.
shader_type canvas_item;

uniform float flash : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 tex = texture(TEXTURE, UV) * COLOR;
	COLOR = vec4(mix(tex.rgb, vec3(1.0), flash), tex.a);
}
