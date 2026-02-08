shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Wet road surface shader for MIDNIGHT GRIND weather system.
// Adds reflective wet surfaces, puddle spots, specular highlights from
// headlights/street lights, and wet tire track marks.
// Integrates with the retro PSX aesthetic while adding modern wet look.

// ── Base Surface ────────────────────────────────────────────────────────────
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform vec4 albedo_color : source_color = vec4(0.15, 0.15, 0.15, 1.0);

// ── Wetness Parameters ──────────────────────────────────────────────────────
// Overall wetness level (0 = dry, 1 = fully wet)
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
// Amount of puddle formation (0 = none, 1 = lots of puddles)
uniform float puddle_amount : hint_range(0.0, 1.0) = 0.0;
// Strength of reflections on wet surface
uniform float reflection_strength : hint_range(0.0, 1.0) = 0.5;

// ── Puddle Noise ────────────────────────────────────────────────────────────
// Noise texture for puddle placement and shape variation
uniform sampler2D puddle_noise : filter_linear_mipmap, repeat_enable;
// Scale of the puddle noise pattern
uniform float puddle_scale : hint_range(0.01, 2.0) = 0.3;
// Threshold below which noise creates a puddle (lower = fewer puddles)
uniform float puddle_threshold : hint_range(0.0, 1.0) = 0.4;

// ── Tire Tracks ─────────────────────────────────────────────────────────────
// Optional tire track mask texture
uniform sampler2D tire_track_texture : filter_linear_mipmap;
// Enable tire track darkening on wet surface
uniform float tire_track_intensity : hint_range(0.0, 1.0) = 0.0;

// ── Reflection ──────────────────────────────────────────────────────────────
// Screen-space reflection approximation color tint
uniform vec4 reflection_tint : source_color = vec4(0.3, 0.35, 0.45, 1.0);
// Fresnel effect strength (glancing angles more reflective)
uniform float fresnel_power : hint_range(1.0, 10.0) = 4.0;

// ── Ripple Animation ────────────────────────────────────────────────────────
// Rain ripple speed (animated concentric rings in puddles)
uniform float ripple_speed : hint_range(0.0, 10.0) = 3.0;
// Ripple distortion strength
uniform float ripple_strength : hint_range(0.0, 0.1) = 0.02;

// ── PSX Vertex Snap ─────────────────────────────────────────────────────────
uniform float vertex_snap_intensity : hint_range(0.0, 1.0) = 0.3;

// Varyings
varying vec3 v_world_pos;
varying vec3 v_world_normal;


// ── Hash function for procedural noise ──────────────────────────────────────
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}


// ── Simple procedural noise fallback ────────────────────────────────────────
float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f); // smoothstep

	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));

	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}


// ── Rain ripple function ────────────────────────────────────────────────────
float rain_ripple(vec2 uv, float time) {
	float ripple = 0.0;
	// Multiple ripple sources at random positions
	for (int i = 0; i < 4; i++) {
		vec2 center = vec2(
			hash(vec2(float(i) * 1.23, 0.0)),
			hash(vec2(0.0, float(i) * 2.47))
		);
		float dist = distance(fract(uv * 3.0), center);
		float ring = sin(dist * 25.0 - time * ripple_speed + float(i) * 1.5);
		ring = max(ring, 0.0);
		ring *= smoothstep(0.5, 0.0, dist); // Fade at edges
		ripple += ring;
	}
	return ripple * 0.25;
}


void vertex() {
	// PSX vertex snapping (lighter than the full retro shader for roads)
	if (vertex_snap_intensity > 0.0) {
		vec4 clip_pos = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
		float snap = mix(1.0, 120.0, vertex_snap_intensity);
		clip_pos.xyz = floor(clip_pos.xyz / clip_pos.w * snap + 0.5) / snap * clip_pos.w;
		POSITION = clip_pos;
	}

	// Pass world position and normal for reflection calculation
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}


void fragment() {
	// ── Base surface ────────────────────────────────────────────────────────
	vec4 base_tex = texture(albedo_texture, UV);
	vec3 base_color = base_tex.rgb * albedo_color.rgb;

	// ── Wetness darkening ───────────────────────────────────────────────────
	// Wet surfaces appear darker (absorbed light)
	float wet_darken = mix(1.0, 0.55, wetness);
	vec3 wet_color = base_color * wet_darken;

	// ── Puddle detection ────────────────────────────────────────────────────
	float puddle_noise_val;
	// Use noise texture if available, otherwise procedural
	vec2 puddle_uv = v_world_pos.xz * puddle_scale;
	puddle_noise_val = value_noise(puddle_uv * 5.0) * 0.5 + value_noise(puddle_uv * 11.0) * 0.3 + value_noise(puddle_uv * 23.0) * 0.2;

	// Puddle mask: areas where water collects
	float puddle_mask = smoothstep(puddle_threshold, puddle_threshold - 0.15, puddle_noise_val);
	puddle_mask *= puddle_amount * wetness;

	// Puddles are darker and more reflective
	float puddle_darken = mix(1.0, 0.4, puddle_mask);
	wet_color *= puddle_darken;

	// ── Tire track marks ────────────────────────────────────────────────────
	if (tire_track_intensity > 0.0) {
		float track = texture(tire_track_texture, UV).r;
		float track_effect = track * tire_track_intensity * wetness;
		wet_color *= mix(1.0, 0.7, track_effect); // Darker wet tracks
	}

	// ── Rain ripples in puddles ─────────────────────────────────────────────
	vec3 normal_offset = vec3(0.0);
	if (puddle_mask > 0.01 && wetness > 0.3) {
		float ripple = rain_ripple(v_world_pos.xz, TIME);
		normal_offset = vec3(
			ripple * ripple_strength * puddle_mask,
			0.0,
			ripple * ripple_strength * puddle_mask * 0.7
		);
	}

	// ── Reflectivity ────────────────────────────────────────────────────────
	// Fresnel: more reflective at glancing angles
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	float fresnel = pow(1.0 - max(dot(v_world_normal, view_dir), 0.0), fresnel_power);

	// Wet surface base reflectivity
	float base_reflectivity = wetness * reflection_strength * 0.3;
	// Puddles are much more reflective
	float puddle_reflectivity = puddle_mask * reflection_strength * 0.8;
	float total_reflectivity = (base_reflectivity + puddle_reflectivity) * (0.5 + fresnel * 0.5);

	// Blend reflection tint into the surface color
	wet_color = mix(wet_color, reflection_tint.rgb, total_reflectivity);

	// ── Specular highlights ─────────────────────────────────────────────────
	// Wet surfaces have much stronger specular (smooth water layer)
	float spec_roughness = mix(0.8, 0.05, wetness * 0.7 + puddle_mask * 0.3);
	float spec_metallic = mix(0.0, 0.2, puddle_mask * wetness);

	// ── Output ──────────────────────────────────────────────────────────────
	ALBEDO = wet_color;
	ROUGHNESS = spec_roughness;
	METALLIC = spec_metallic;
	NORMAL_MAP = normalize(vec3(0.5 + normal_offset.x, 0.5 + normal_offset.z, 1.0));
	NORMAL_MAP_DEPTH = wetness * 0.5;
	ALPHA = 1.0;
}
