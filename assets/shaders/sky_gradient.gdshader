shader_type sky;

// Sky gradient shader for MIDNIGHT GRIND day/night cycle.
// Procedural sky with gradient blending, star field, moon disc, and cloud wisps.

uniform vec3 sky_top_color : source_color = vec3(0.03, 0.03, 0.12);
uniform vec3 sky_horizon_color : source_color = vec3(0.06, 0.04, 0.18);
uniform vec3 sky_ground_color : source_color = vec3(0.02, 0.01, 0.06);

// Star parameters
uniform float star_visibility : hint_range(0.0, 1.0) = 1.0;
uniform float star_density : hint_range(50.0, 500.0) = 200.0;
uniform float star_brightness : hint_range(0.0, 2.0) = 1.0;
uniform float star_twinkle_speed : hint_range(0.0, 5.0) = 1.5;

// Moon parameters
uniform vec3 moon_direction = vec3(0.3, 0.6, -0.4);
uniform float moon_size : hint_range(0.005, 0.05) = 0.02;
uniform float moon_glow_size : hint_range(0.02, 0.2) = 0.08;
uniform float moon_intensity : hint_range(0.0, 1.5) = 0.3;
uniform vec3 moon_color : source_color = vec3(0.85, 0.9, 1.0);
uniform float moon_phase : hint_range(0.0, 1.0) = 0.5;

// Cloud parameters
uniform float cloud_density : hint_range(0.0, 1.0) = 0.3;
uniform float cloud_speed : hint_range(0.0, 0.1) = 0.01;
uniform vec3 cloud_color : source_color = vec3(0.15, 0.12, 0.25);
uniform float cloud_opacity : hint_range(0.0, 1.0) = 0.3;

// Horizon glow (city light pollution)
uniform vec3 horizon_glow_color : source_color = vec3(0.12, 0.05, 0.15);
uniform float horizon_glow_strength : hint_range(0.0, 1.0) = 0.4;


// Hash functions for procedural generation
float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

// Simplex-like noise for clouds
float noise2d(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));

	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Fractal Brownian motion for cloud shapes
float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;
	for (int i = 0; i < 4; i++) {
		value += amplitude * noise2d(p * frequency);
		amplitude *= 0.5;
		frequency *= 2.0;
	}
	return value;
}


void sky() {
	vec3 dir = EYEDIR;
	float y = dir.y;

	// --- Base sky gradient ---
	vec3 col;
	if (y > 0.0) {
		// Above horizon: blend horizon -> top
		float t = pow(y, 0.6);
		col = mix(sky_horizon_color, sky_top_color, t);
	} else {
		// Below horizon: blend horizon -> ground
		float t = pow(-y, 0.4);
		col = mix(sky_horizon_color, sky_ground_color, t);
	}

	// --- Horizon glow (light pollution from city) ---
	float horizon_factor = exp(-abs(y) * 8.0);
	col += horizon_glow_color * horizon_glow_strength * horizon_factor;

	// --- Stars (only above horizon) ---
	if (star_visibility > 0.01 && y > 0.0) {
		// Project onto a virtual sphere for stable star positions
		vec2 star_uv = dir.xz / (y + 0.001) * star_density;
		vec2 star_cell = floor(star_uv);
		vec2 star_fract = fract(star_uv);

		float star_hash = hash21(star_cell);

		// Only some cells have stars
		if (star_hash > 0.92) {
			// Star position within cell
			vec2 star_pos = vec2(hash21(star_cell + 0.5), hash21(star_cell + 1.5));
			float dist = length(star_fract - star_pos);

			// Star point with slight glow
			float star = smoothstep(0.06, 0.0, dist);

			// Twinkle effect (each star twinkles at its own rate)
			float twinkle_phase = star_hash * 6.28;
			float twinkle_rate = 0.5 + star_hash * 2.0;
			float twinkle = 0.6 + 0.4 * sin(TIME * star_twinkle_speed * twinkle_rate + twinkle_phase);

			// Star color variation (mostly white, some slightly blue/yellow)
			vec3 star_col = vec3(1.0);
			if (star_hash > 0.97) {
				star_col = vec3(0.8, 0.85, 1.0); // Blue-ish
			} else if (star_hash > 0.95) {
				star_col = vec3(1.0, 0.95, 0.8); // Warm-ish
			}

			col += star_col * star * star_brightness * twinkle * star_visibility;
		}
	}

	// --- Moon ---
	if (moon_intensity > 0.01) {
		vec3 moon_dir = normalize(moon_direction);
		float moon_dot = dot(dir, moon_dir);
		float moon_angle = acos(clamp(moon_dot, -1.0, 1.0));

		// Moon disc
		if (moon_angle < moon_size) {
			float disc = smoothstep(moon_size, moon_size * 0.7, moon_angle);

			// Moon phase: offset a dark circle to create crescent
			vec3 moon_right = normalize(cross(moon_dir, vec3(0.0, 1.0, 0.0)));
			float phase_offset = (moon_phase - 0.5) * 2.0; // -1 to 1
			vec3 shadow_dir = moon_dir + moon_right * phase_offset * moon_size * 30.0;
			float shadow_dot = dot(dir, normalize(shadow_dir));
			float shadow_angle = acos(clamp(shadow_dot, -1.0, 1.0));
			float shadow = smoothstep(moon_size * 0.9, moon_size * 0.5, shadow_angle);

			float lit = disc * (1.0 - shadow * 0.85);
			col += moon_color * lit * moon_intensity * 2.0;
		}

		// Moon glow (atmospheric scatter around moon)
		float glow = exp(-moon_angle * moon_angle / (moon_glow_size * moon_glow_size));
		col += moon_color * glow * moon_intensity * 0.3;
	}

	// --- Cloud wisps ---
	if (cloud_density > 0.01 && y > -0.1) {
		// Project clouds onto a dome
		vec2 cloud_uv = dir.xz / (max(y, 0.05)) * 2.0;
		cloud_uv += vec2(TIME * cloud_speed, TIME * cloud_speed * 0.3);

		float cloud = fbm(cloud_uv * 3.0);
		cloud = smoothstep(0.5 - cloud_density * 0.3, 0.8, cloud);

		// Clouds thin out at zenith, thicker near horizon
		float height_fade = smoothstep(0.8, 0.1, y);
		cloud *= height_fade * cloud_opacity;

		// Cloud color: slightly lit by moon at night, by sun during day
		vec3 lit_cloud = cloud_color + moon_color * moon_intensity * 0.1;
		col = mix(col, lit_cloud, cloud);
	}

	COLOR = col;
}
