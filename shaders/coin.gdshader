// coin.gdshader
// Procedural spinning gold coin (no texture): the Sprite2D/Coin ColorRect of
// scenes/collectibles/energy_collectible_1.tscn (the energy coin, 5 points).
// Everything is computed from UV (0..1 across the square quad):
//
//   q = (UV - 0.5) * quad_px   (pixels from the center; keep quad_px equal
//                               to the ColorRect's size)
//   p = q / radius_px          (coin units: face radius 1)
//
// The coin is a short cylinder (face radius 1, thickness `thickness`) turned
// about the vertical axis by spin_angle (radians, set every frame by
// energy_collectible.gd: own random phase and speed per coin, pause-safe).
// Seen orthographically:
// - Silhouette: the face ellipse (half-width |cos|, height 1) swept sideways
//   by the edge, half-length 0.5 * thickness * |sin|, so an edge-on coin is
//   still a band ~thickness + 0.12 coin units wide (never vanishes).
// - Visible face: the front face while cos > 0, the back face (tinted with
//   back_tint) while cos < 0; its ellipse sits on the side of the band the
//   face is on, the rest of the silhouette is the edge band (cylinder side,
//   lit with its real normal, soft reeding).
// - Face: raised rim (rim_inner .. rim_outer, bevelled to the edge) and the
//   embossed emblem (emblem: 0 microchip, 1 five-point star, 2 lightning
//   bolt), shaded by sampling the height twice along the face-local light
//   direction (classic emboss); flat diffuse that changes with the spin,
//   capped at face_lum_max so a fully lit face stays gold (not cream) and
//   the relief never clips away; a darker groove (groove_px,
//   groove_strength) traces the emblem and the rim's inner edge and is
//   applied after the glint, so the emblem reads at every open phase
//   whatever the light; a narrow specular glint band sweeping across the
//   front face once per turn.
//   Emblem and rim detail fade out at the thin phases (they would only
//   shimmer there) and the face blends into the edge colour when edge-on.
// - Thin dark outline (outline_px) around the silhouette, then a soft warm
//   glow (glow_px, glow_strength) for the dark skies; a short four-point
//   twinkle on the upper-left edge of the visible face, driven by its own
//   wrapped twinkle_phase (0..1, set by the script with its own period,
//   independent of the spin) and shown only while the face is open.
// - COLOR (the rect colour x modulate) is multiplied last, so modulate
//   tweens apply on top. Standard alpha blending.
//
// GLES3 / Mobile safe and cheap: no texture reads, no derivatives, no screen
// reads. The spin's sin/cos, the glint position, the twinkle (strength and
// centre) and the light vectors are computed per vertex (4 vertices); both
// driving uniforms stay small (spin_angle 0..TAU, twinkle_phase 0..1), so
// mediump precision is enough; per fragment there are no
// trig calls, ~4 sqrt/length, one non-uniform branch (skip the coin body
// outside the silhouette) and one uniform branch (emblem choice). The
// lightning bolt is a 6-edge polygon distance (unrolled, evaluated twice).
shader_type canvas_item;

// Spin angle in radians, 0..TAU (set per frame by the script)
uniform float spin_angle = 0.0;
// Twinkle cycle position, 0..1 (set per frame by the script; the twinkle
// plays over the first twinkle_len of each cycle)
uniform float twinkle_phase = 0.5;
// 0 = microchip, 1 = five-point star (default, the shipped coin), 2 = lightning
// bolt. This shader default is the single source of truth: the coin scene's
// material stores no emblem override
uniform int emblem : hint_enum("Microchip", "Star", "Lightning bolt") = 1;

// Geometry (pixels; quad_px must equal the ColorRect's size)
uniform float quad_px = 56.0;
uniform float radius_px = 16.0;
// Edge thickness in face radii (edge-on band width)
uniform float thickness : hint_range(0.05, 0.5) = 0.24;
// Raised rim on the face (face radii)
uniform float rim_inner : hint_range(0.4, 0.95) = 0.74;
uniform float rim_outer : hint_range(0.5, 1.0) = 0.9;

// Gold ramp: shadow -> body -> highlight
uniform vec4 gold_dark : source_color = vec4(0.46, 0.25, 0.04, 1.0);
uniform vec4 gold_mid : source_color = vec4(0.93, 0.64, 0.12, 1.0);
uniform vec4 gold_light : source_color = vec4(1.0, 0.93, 0.58, 1.0);
// Brightest flat face value on the ramp (0..1+; ~0.62 keeps a fully lit
// face gold; the emboss highlights and the glint still reach gold_light)
uniform float face_lum_max : hint_range(0.3, 1.0) = 0.62;
// Edge band and back face tints (multiply the ramp)
uniform vec4 edge_tint : source_color = vec4(0.86, 0.72, 0.56, 1.0);
uniform vec4 back_tint : source_color = vec4(1.0, 0.86, 0.74, 1.0);
// Emboss (rim and emblem relief) strength
uniform float emboss_strength : hint_range(0.0, 2.0) = 0.9;
// Dark groove along the emblem edges and the rim's inner edge: half width
// (pixels) and how far it pulls toward gold_dark (0 off .. 1 full);
// light-independent
uniform float groove_px : hint_range(0.3, 3.0) = 1.0;
uniform float groove_strength : hint_range(0.0, 1.0) = 0.42;
// Light direction (screen space: x right, y down, z toward the viewer)
uniform vec3 light_dir = vec3(-0.45, -0.55, 0.7);

// Specular glint band
uniform vec4 glint_color : source_color = vec4(1.0, 1.0, 0.92, 1.0);
uniform float glint_strength : hint_range(0.0, 2.0) = 0.45;
uniform float glint_width : hint_range(0.02, 0.6) = 0.09;

// Outline and glow (pixels)
uniform vec4 outline_color : source_color = vec4(0.17, 0.08, 0.02, 1.0);
uniform float outline_px : hint_range(0.0, 3.0) = 1.25;
uniform vec4 glow_color : source_color = vec4(1.0, 0.72, 0.22, 1.0);
uniform float glow_strength : hint_range(0.0, 1.0) = 0.35;
uniform float glow_px : hint_range(1.0, 12.0) = 7.0;

// Twinkle: brightness, length (fraction of the twinkle_phase cycle; a sin
// pulse), arm length (pixels) and spot on the face (face radii, local x
// right, y down; on the outer rim, so the arms reach out over the sky)
uniform float twinkle_strength : hint_range(0.0, 3.0) = 1.6;
uniform float twinkle_len : hint_range(0.01, 0.5) = 0.08;
uniform float twinkle_px : hint_range(2.0, 14.0) = 10.0;
uniform vec2 twinkle_pos = vec2(-0.62, -0.66);

// x: cos(spin), y: sin(spin), z: glint band center
varying vec3 v_spin;
// xy: twinkle centre (pixels from the quad centre), z: strength 0..1
varying vec3 v_tw;
// xy: face-local light direction (normalized), z: face diffuse
varying vec3 v_light;
// Normalized light (screen space)
varying vec3 v_l;

void vertex() {
	float cs = cos(spin_angle);
	float sn = sin(spin_angle);
	float sg = cs >= 0.0 ? 1.0 : -1.0;
	// 0 .. 0.5 while the front face shows: the glint crosses it then
	float u = fract((spin_angle + 1.5707963) * 0.15915494);
	float glint_c = -1.3 + 2.6 * clamp(u * 2.0, 0.0, 1.0);
	v_spin = vec3(cs, sn, glint_c);
	// Twinkle: sin pulse over the first twinkle_len of its cycle, only
	// while the face is reasonably open; centred on the rim of the visible
	// face (whose ellipse is shifted sideways by the edge band)
	float x = twinkle_phase / twinkle_len;
	float tw = x < 1.0 ? sin(3.14159265 * x) : 0.0;
	tw *= smoothstep(0.45, 0.7, abs(cs));
	float xv = sg * (sn >= 0.0 ? 1.0 : -1.0) * 0.5 * thickness * abs(sn);
	v_tw = vec3(vec2(xv + abs(cs) * twinkle_pos.x, twinkle_pos.y) * radius_px, tw);
	vec3 l = normalize(light_dir);
	v_l = l;
	// Light in the visible face's own axes (local x always points right)
	vec2 l2 = vec2(l.x * abs(cs) - sg * l.z * sn, l.y);
	v_light = vec3(normalize(l2 + vec2(0.0001)), sg * sn * l.x + abs(cs) * l.z);
}

// Cheap ellipse distance (accurate near the boundary, negative inside)
float sd_ellipse(vec2 p, vec2 ab) {
	float k0 = length(p / ab);
	float k1 = length(p / (ab * ab));
	return k1 < 0.0001 ? -min(ab.x, ab.y) : k0 * (k0 - 1.0) / k1;
}

float sd_box(vec2 p, vec2 b, float r) {
	vec2 d = abs(p) - b + r;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

// Microchip: rounded body, two pins per side, recessed square die
// Returns x: relief distance (body + pins), y: die distance
vec2 sd_chip(vec2 p) {
	float body = sd_box(p, vec2(0.31), 0.07);
	vec2 a = abs(p);
	a = a.y > a.x ? a.yx : a;           // fold the four sides onto +x
	float pins = sd_box(vec2(a.x - 0.41, abs(a.y - 0.14)), vec2(0.1, 0.055), 0.0);
	float die = sd_box(p, vec2(0.14), 0.03);
	return vec2(min(body, pins), die);
}

// Five-point star, point up (after iq)
float sd_star(vec2 p, float r, float rf) {
	p.y = -p.y;
	const vec2 k1 = vec2(0.809016994, -0.587785252);
	const vec2 k2 = vec2(-0.809016994, -0.587785252);
	p.x = abs(p.x);
	p -= 2.0 * max(dot(k1, p), 0.0) * k1;
	p -= 2.0 * max(dot(k2, p), 0.0) * k2;
	p.x = abs(p.x);
	p.y -= r;
	vec2 ba = rf * vec2(-k1.y, k1.x) - vec2(0.0, 1.0);
	float h = clamp(dot(p, ba) / dot(ba, ba), 0.0, r);
	return length(p - ba * h) * sign(p.y * ba.x - p.x * ba.y);
}

// One polygon edge (iq's sdPolygon, unrolled by the caller)
void poly_edge(vec2 p, vec2 a, vec2 b, inout float d, inout float s) {
	vec2 e = b - a;
	vec2 w = p - a;
	vec2 bb = w - e * clamp(dot(w, e) / dot(e, e), 0.0, 1.0);
	d = min(d, dot(bb, bb));
	bool c1 = p.y >= a.y;
	bool c2 = p.y < b.y;
	bool c3 = e.x * w.y > e.y * w.x;
	if ((c1 && c2 && c3) || (!c1 && !c2 && !c3)) {
		s = -s;
	}
}

// Lightning bolt (screen space, y down); the polygon is grown by 0.04 face
// radii (~0.6 px) so its stroke holds up at game size
float sd_bolt(vec2 p) {
	vec2 v0 = vec2(0.14, -0.58);
	vec2 v1 = vec2(-0.30, 0.06);
	vec2 v2 = vec2(-0.02, 0.06);
	vec2 v3 = vec2(-0.14, 0.58);
	vec2 v4 = vec2(0.30, -0.08);
	vec2 v5 = vec2(0.02, -0.08);
	float d = dot(p - v0, p - v0);
	float s = 1.0;
	poly_edge(p, v5, v0, d, s);
	poly_edge(p, v0, v1, d, s);
	poly_edge(p, v1, v2, d, s);
	poly_edge(p, v2, v3, d, s);
	poly_edge(p, v3, v4, d, s);
	poly_edge(p, v4, v5, d, s);
	return s * sqrt(d) - 0.04;
}

// Face relief at face-local point lp (rim + emblem)
// Returns x: height, y: distance to the nearest groove line (the emblem
// edges and the rim's inner edge, face radii)
vec2 face_height(vec2 lp, float aa) {
	float r = length(lp);
	float h = smoothstep(rim_inner - 0.06, rim_inner, r) * (1.0 - 0.6 * smoothstep(rim_outer, 1.0, r));
	float he;
	float g;
	if (emblem == 1) {
		float d = sd_star(lp, 0.56, 0.45);
		he = 1.0 - smoothstep(-aa, aa, d);
		g = abs(d);
	} else if (emblem == 2) {
		float d = sd_bolt(lp);
		he = 1.0 - smoothstep(-aa, aa, d);
		g = abs(d);
	} else {
		vec2 c = sd_chip(lp);
		he = 1.0 - smoothstep(-aa, aa, c.x);
		he -= 0.6 * (1.0 - smoothstep(-aa, aa, c.y));
		g = min(abs(c.x), abs(c.y));
	}
	g = min(g, abs(r - rim_inner + 0.03));
	return vec2(h + 0.9 * he, g);
}

// Gold ramp, v 0..1+
vec3 gold(float v) {
	vec3 lo = mix(gold_dark.rgb, gold_mid.rgb, clamp(v * 1.8, 0.0, 1.0));
	return mix(lo, gold_light.rgb, clamp(v * 1.8 - 0.8, 0.0, 1.0));
}

void fragment() {
	vec2 q = (UV - 0.5) * quad_px;
	vec2 p = q / radius_px;
	float px = 1.0 / radius_px;          // one pixel in coin units
	float cs = v_spin.x;
	float sn = v_spin.y;
	float c = max(abs(cs), 0.06);        // face half-width (min ~1 px)
	float sgs = sn >= 0.0 ? 1.0 : -1.0;
	float sgc = cs >= 0.0 ? 1.0 : -1.0;
	float hs = 0.5 * thickness * abs(sn);

	// Silhouette distance (pixels, < 0 inside)
	vec2 ph = vec2(p.x - clamp(p.x, -hs, hs), p.y);
	// The cheap ellipse distance underestimates far from a thin ellipse;
	// the true distance is at least the box distance, so take the max
	float d_sil = max(sd_ellipse(ph, vec2(c, 1.0)), max(abs(ph.x) - c, abs(p.y) - 1.0)) * radius_px;

	vec3 col = glow_color.rgb;
	float g = clamp(1.0 - (d_sil - outline_px) / glow_px, 0.0, 1.0);
	float a = g * g * glow_strength;

	if (d_sil < 0.6) {
		// Edge band: cylinder side, real normal at this height
		float w = sqrt(max(1.0 - p.y * p.y, 0.0));
		vec3 n_side = vec3(-sgs * w * cs, p.y, w * abs(sn));
		float band_l = clamp(0.3 + 0.7 * dot(n_side, v_l), 0.0, 1.0);
		float rib = abs(fract(p.y * 5.0) - 0.5);
		vec3 band_col = gold(band_l * (0.8 + 0.4 * rib)) * edge_tint.rgb;

		// Visible face
		float xv = sgc * sgs * hs;
		vec2 pf = vec2(p.x - xv, p.y);
		float d_face = sd_ellipse(pf, vec2(c, 1.0)) * radius_px;
		float face_m = 1.0 - smoothstep(-0.5, 0.5, d_face);
		vec2 lp = vec2(pf.x / c, pf.y);
		float detail = smoothstep(0.14, 0.42, abs(cs));
		float aa = 0.7 * px;
		vec2 e = v_light.xy * px;
		vec2 f0 = face_height(lp - e, aa);
		vec2 f1 = face_height(lp + e, aa);
		float emboss = (f0.x - f1.x) * detail;
		float raised = 0.5 * (f0.x + f1.x) * detail;
		// Flat face light capped so full light stays gold and the relief
		// (+-emboss) never clips into the cream end of the ramp
		float lum = min(0.16 + 0.56 * v_light.z, face_lum_max) + emboss * emboss_strength + 0.06 * raised;
		vec3 face_col = gold(lum);
		face_col *= sgc > 0.0 ? vec3(1.0) : back_tint.rgb;
		// Glint band sweeping across the front face
		float gl = dot(lp, vec2(0.7071)) - v_spin.z;
		float glint = 1.0 - smoothstep(0.0, glint_width, abs(gl));
		glint += 0.5 * (1.0 - smoothstep(0.0, glint_width * 0.4, abs(gl + glint_width * 2.2)));
		face_col += glint_color.rgb * glint * glint_strength * smoothstep(0.25, 0.6, abs(cs));
		// Groove after the glint: the emblem outline survives full light
		// and the glint band
		float groove = 1.0 - smoothstep(0.4 * groove_px * px, groove_px * px, min(f0.y, f1.y));
		face_col = mix(face_col, gold_dark.rgb, groove_strength * groove * detail);

		float face_vis = face_m * smoothstep(0.0, 0.12, abs(cs));
		vec3 coin = mix(band_col, face_col, face_vis);
		// Dark seam where the face meets the band
		float seam = (1.0 - smoothstep(0.0, 0.9, abs(d_face + 0.4))) * smoothstep(0.01, 0.05, hs);
		coin *= 1.0 - 0.3 * seam;

		float a_out = 1.0 - smoothstep(outline_px - 0.5, outline_px + 0.5, d_sil);
		float a_coin = 1.0 - smoothstep(-0.5, 0.5, d_sil);
		col = mix(col, outline_color.rgb, a_out);
		a = mix(a, 1.0, a_out);
		col = mix(col, coin, a_coin);
	} else {
		float a_out = 1.0 - smoothstep(outline_px - 0.5, outline_px + 0.5, d_sil);
		col = mix(col, outline_color.rgb, a_out);
		a = mix(a, 1.0, a_out);
	}

	// Twinkle (on the rim, upper left of the visible face)
	vec2 d = abs(q - v_tw.xy);
	float arm = twinkle_px;
	float star = max(0.0, 1.0 - d.x / arm - d.y / 1.4) + max(0.0, 1.0 - d.y / arm - d.x / 1.4);
	star += max(0.0, 1.0 - length(d) / 3.0);
	float sp = clamp(star * v_tw.z * twinkle_strength, 0.0, 1.0);
	col = mix(col, vec3(1.0, 0.98, 0.88), sp);
	a = max(a, sp);

	COLOR = vec4(col, a) * COLOR;
}
