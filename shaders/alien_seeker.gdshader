// alien_seeker.gdshader
// Procedural seeker orb (no texture): the Glow ColorRect of
// scenes/effects/alien_seeker.tscn (the Alien Mothership's homing orbs).
// Everything is computed from UV (0..1 across the square quad):
//
//   p = (UV - 0.5) * 2   (quad edge at |p| = 1)
//
// - Halo: soft magenta glow falling off to 0 at the quad edge.
// - Shell: a brighter magenta ring at shell_radius (the orb's edge).
// - Core: an alien-green core whose radius and brightness pulse
//   (pulse_speed, TIME), with a white-hot center.
// - COLOR (the rect color x modulate) is multiplied last, so the code-driven
//   hit flash and fast-blink tell in alien_seeker.gd apply on top. No
//   texture is sampled. Standard alpha blending.
//
// GLES3 / Mobile safe and cheap: no texture reads, no loops, no derivatives.
shader_type canvas_item;

uniform vec4 halo_color : source_color = vec4(0.95, 0.2, 0.85, 1.0);
uniform float halo_strength : hint_range(0.0, 2.0) = 0.8;
uniform float shell_radius : hint_range(0.1, 0.9) = 0.5;
uniform float shell_width : hint_range(0.01, 0.4) = 0.12;
uniform vec4 shell_color : source_color = vec4(1.0, 0.45, 0.95, 1.0);
uniform vec4 core_color : source_color = vec4(0.45, 1.0, 0.35, 1.0);
uniform float core_radius : hint_range(0.05, 0.6) = 0.34;
uniform float pulse_speed = 7.0;
uniform float pulse_amount : hint_range(0.0, 0.5) = 0.2;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float pulse = 0.5 + 0.5 * sin(TIME * pulse_speed);

	// Halo: 1 at the shell, 0 at the quad edge
	float halo = 1.0 - smoothstep(shell_radius, 1.0, r);
	halo = halo * halo * halo_strength;

	// Shell ring
	float shell = 1.0 - smoothstep(0.0, shell_width, abs(r - shell_radius));
	// Inside the shell: dark magenta body so the core reads
	float body = 1.0 - smoothstep(shell_radius - 0.04, shell_radius + 0.02, r);

	// Pulsing core
	float cr = core_radius * (1.0 + pulse_amount * (pulse - 0.5) * 2.0);
	float core = 1.0 - smoothstep(cr * 0.4, cr, r);
	float hot = 1.0 - smoothstep(0.0, cr * 0.45, r);

	vec3 col = halo_color.rgb * 0.6;
	col = mix(col, vec3(0.35, 0.05, 0.4), body);
	col = mix(col, shell_color.rgb, shell);
	col = mix(col, core_color.rgb * (0.85 + 0.35 * pulse), core);
	col = mix(col, vec3(1.0), hot * 0.8);
	float a = max(max(halo, body), max(shell, core));
	COLOR = vec4(col * COLOR.rgb, clamp(a, 0.0, 1.0) * COLOR.a);
}
