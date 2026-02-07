// Ghost Vehicle Shader — MIDNIGHT GRIND
// Semi-transparent spatial shader with pulsing opacity, Fresnel rim lighting,
// and configurable tint for era-coded ghost vehicles (Act 1-4 colours).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, unshaded;

// ── Uniforms ──────────────────────────────────────────────────────────────────
// Base ghost colour tint (set per-era by GhostPlayer).
uniform vec4 ghost_color : source_color = vec4(0.3, 0.95, 1.0, 1.0);
// Resting opacity before pulsing is applied.
uniform float base_opacity : hint_range(0.0, 1.0) = 0.4;
// Speed of the sine-wave opacity pulse (cycles per second).
uniform float pulse_speed : hint_range(0.0, 10.0) = 2.0;
// Amplitude of the opacity pulse (added/subtracted from base_opacity).
uniform float pulse_amplitude : hint_range(0.0, 0.3) = 0.1;
// Fresnel exponent — higher = thinner rim glow.
uniform float fresnel_power : hint_range(0.5, 8.0) = 3.0;
// Brightness multiplier for the Fresnel rim.
uniform float rim_intensity : hint_range(0.0, 4.0) = 1.5;
// Overall emission brightness (makes the ghost glow in dark scenes).
uniform float emission_strength : hint_range(0.0, 5.0) = 0.8;
// Subtle UV distortion for a "heat haze" / unstable ghost look.
uniform float distortion_amount : hint_range(0.0, 0.05) = 0.008;
// Speed of the distortion scroll.
uniform float distortion_speed : hint_range(0.0, 5.0) = 1.5;
// Scanline density (retro PS1/PS2 aesthetic touch).
uniform float scanline_density : hint_range(0.0, 200.0) = 60.0;
// Scanline intensity (0 = off).
uniform float scanline_intensity : hint_range(0.0, 0.5) = 0.08;

// ── Vertex ────────────────────────────────────────────────────────────────────
void vertex() {
	// Subtle vertex wobble along normals for a "phasing in/out" feel.
	float wobble = sin(TIME * pulse_speed * 1.5 + VERTEX.y * 4.0) * 0.005;
	VERTEX += NORMAL * wobble;
}

// ── Fragment ──────────────────────────────────────────────────────────────────
void fragment() {
	// ── Base colour ──
	vec3 base_col = ghost_color.rgb;

	// ── Fresnel rim ──
	// VIEW is the camera direction in view space; NORMAL is the surface normal.
	float fresnel = pow(1.0 - abs(dot(NORMAL, VIEW)), fresnel_power);
	vec3 rim_col = base_col * rim_intensity * fresnel;

	// ── Pulsing opacity ──
	float pulse = sin(TIME * pulse_speed * 6.2831853) * pulse_amplitude;
	float opacity = clamp(base_opacity + pulse, 0.0, 1.0);

	// Fresnel adds opacity at edges (ghostly rim glow)
	opacity = clamp(opacity + fresnel * 0.3, 0.0, 1.0);

	// ── Scanlines (retro aesthetic) ──
	float scanline = 1.0 - scanline_intensity * step(0.5, fract(SCREEN_UV.y * scanline_density));

	// ── Distortion ──
	// Offset UV slightly over time for a shimmering instability.
	float dist_offset = sin(TIME * distortion_speed + UV.y * 10.0) * distortion_amount;
	// We can't distort the actual surface UV meaningfully on a BoxMesh,
	// but we use the offset to modulate colour subtly.
	float dist_mod = 1.0 + dist_offset * 5.0;

	// ── Compose ──
	vec3 final_color = (base_col * 0.6 + rim_col) * scanline * dist_mod;

	ALBEDO = final_color;
	ALPHA = opacity;
	EMISSION = final_color * emission_strength;
}
