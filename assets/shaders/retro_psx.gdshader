shader_type spatial;
render_mode unshaded, vertex_lighting;

// PS1-style vertex snapping and affine texture mapping shader.
// Core of the MIDNIGHT GRIND retro aesthetic per GDD Section 2.1.

uniform float vertex_snap_intensity : hint_range(0.0, 1.0) = 0.5;
uniform float affine_intensity : hint_range(0.0, 1.0) = 0.7;
uniform sampler2D albedo_texture : source_color;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float emission_strength : hint_range(0.0, 5.0) = 0.0;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

varying float v_affine_w;

void vertex() {
	// PS1 vertex snapping
	vec4 clip_pos = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);

	// Snap vertices to simulated low-resolution grid
	float snap_amount = mix(1.0, 160.0, vertex_snap_intensity);
	clip_pos.xyz = floor(clip_pos.xyz / clip_pos.w * snap_amount + 0.5) / snap_amount * clip_pos.w;

	// Store W for affine correction
	v_affine_w = clip_pos.w;

	// Apply vertex lighting jitter
	POSITION = clip_pos;
}

void fragment() {
	// Affine texture mapping (PS1 style — no perspective correction)
	vec2 uv = UV;
	if (affine_intensity > 0.0) {
		vec2 affine_uv = UV * v_affine_w;
		uv = mix(UV, affine_uv / v_affine_w, affine_intensity);
	}

	vec4 tex = texture(albedo_texture, uv);
	ALBEDO = tex.rgb * albedo_color.rgb;
	ALPHA = tex.a * albedo_color.a;

	// Emission for neon elements
	if (emission_strength > 0.0) {
		EMISSION = emission_color.rgb * emission_strength;
	}
}
