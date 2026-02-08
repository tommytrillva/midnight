shader_type canvas_item;

// Rain on windshield/camera overlay shader for MIDNIGHT GRIND.
// Renders rain streaks running down the screen, water droplet distortion,
// and an optional wiper clear zone. Designed as a 2D overlay on a
// full-screen ColorRect via CanvasLayer.

// ── Rain Parameters ─────────────────────────────────────────────────────────
// Overall rain intensity (0 = dry, 1 = storm)
uniform float rain_intensity : hint_range(0.0, 1.0) = 0.0;
// Wind angle affecting streak direction (radians, 0 = straight down)
uniform float wind_angle : hint_range(-1.57, 1.57) = 0.0;

// ── Streak Configuration ────────────────────────────────────────────────────
// Speed at which streaks travel down the screen
uniform float streak_speed : hint_range(0.1, 5.0) = 1.5;
// Number of streak columns across the screen
uniform float streak_columns : hint_range(5.0, 80.0) = 30.0;
// Length of individual streaks (fraction of screen height)
uniform float streak_length : hint_range(0.02, 0.5) = 0.15;
// Width of streaks (fraction of screen width per column)
uniform float streak_width : hint_range(0.1, 0.8) = 0.3;

// ── Droplet Configuration ───────────────────────────────────────────────────
// Density of small static water droplets
uniform float droplet_density : hint_range(0.0, 1.0) = 0.3;
// Distortion amount from droplets (refractive effect)
uniform float droplet_distortion : hint_range(0.0, 0.05) = 0.01;

// ── Wiper Effect ────────────────────────────────────────────────────────────
// Enable windshield wiper clearing arc
uniform bool wiper_enabled = false;
// Wiper sweep progress (0 to 1 for one sweep)
uniform float wiper_progress : hint_range(0.0, 1.0) = 0.0;
// How clear the wiped area is (1 = fully clear)
uniform float wiper_clear : hint_range(0.0, 1.0) = 0.8;

// ── Visual ──────────────────────────────────────────────────────────────────
// Tint for the rain overlay
uniform vec4 rain_tint : source_color = vec4(0.7, 0.75, 0.85, 1.0);
// Background scene texture (screen texture for distortion)
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;


// ── Hash functions for procedural randomness ────────────────────────────────
float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}


// ── Rain streak function ────────────────────────────────────────────────────
// Returns (streak_mask, streak_distortion_x, streak_distortion_y)
vec3 rain_streak(vec2 uv, float time) {
	float result = 0.0;
	vec2 distort = vec2(0.0);

	// Apply wind angle rotation to UV for angled streaks
	float s = sin(wind_angle * 0.5);
	float c = cos(wind_angle * 0.5);
	vec2 rotated_uv = vec2(
		uv.x * c - uv.y * s,
		uv.x * s + uv.y * c
	);

	// Multiple layers of streaks for depth
	for (int layer = 0; layer < 3; layer++) {
		float layer_f = float(layer);
		float layer_speed = streak_speed * (1.0 + layer_f * 0.3);
		float layer_scale = streak_columns * (1.0 + layer_f * 0.5);
		float layer_alpha = 1.0 - layer_f * 0.3;

		// Grid-based streak placement
		vec2 grid_uv = rotated_uv * vec2(layer_scale, 1.0);
		float column = floor(grid_uv.x);

		// Random properties per column
		float col_seed = hash11(column + layer_f * 100.0);
		float col_speed = layer_speed * (0.7 + col_seed * 0.6);
		float col_offset = hash11(column * 1.37 + layer_f * 50.0);
		float col_width = streak_width * (0.5 + col_seed * 0.5);

		// Horizontal position within column
		float local_x = fract(grid_uv.x) - 0.5;
		float x_mask = smoothstep(col_width * 0.5, col_width * 0.1, abs(local_x));

		// Vertical streak animation (falling)
		float fall = fract(rotated_uv.y * 2.0 - time * col_speed + col_offset);

		// Streak shape: tapered head, thin body, tapered tail
		float streak_mask = smoothstep(0.0, streak_length * 0.2, fall)
						  * smoothstep(streak_length, streak_length * 0.7, fall);

		// Only show streak if this column is "active" (based on intensity)
		float active = step(col_seed, rain_intensity * 1.2);

		float streak = x_mask * streak_mask * active * layer_alpha;
		result += streak;

		// Distortion from streaks (slight refraction)
		distort += vec2(local_x, fall - 0.5) * streak * droplet_distortion;
	}

	return vec3(clamp(result, 0.0, 1.0), distort);
}


// ── Water droplet function ──────────────────────────────────────────────────
vec3 water_droplets(vec2 uv) {
	float mask = 0.0;
	vec2 distort = vec2(0.0);

	// Grid of potential droplet positions
	vec2 grid = uv * 50.0;
	vec2 cell = floor(grid);
	vec2 local = fract(grid) - 0.5;

	// Check neighboring cells for droplets
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbor = vec2(float(x), float(y));
			vec2 cell_pos = cell + neighbor;

			// Random droplet position within cell
			vec2 drop_pos = hash22(cell_pos) - 0.5;
			float drop_size = hash21(cell_pos * 1.23) * 0.15 + 0.05;

			// Only create droplet if random value is below density threshold
			float active = step(hash21(cell_pos * 2.47), droplet_density * rain_intensity);

			vec2 diff = local - neighbor - drop_pos;
			float dist = length(diff);

			// Circular droplet shape
			float drop = smoothstep(drop_size, drop_size * 0.3, dist) * active;
			mask += drop;

			// Refraction distortion (lens effect)
			if (drop > 0.01) {
				distort += normalize(diff) * drop * droplet_distortion * 2.0;
			}
		}
	}

	return vec3(clamp(mask, 0.0, 1.0), distort);
}


// ── Wiper clear zone ────────────────────────────────────────────────────────
float wiper_mask(vec2 uv) {
	if (!wiper_enabled) return 0.0;

	// Wiper pivots from bottom-center, sweeps in an arc
	vec2 pivot = vec2(0.5, 1.1);
	vec2 to_point = uv - pivot;
	float angle = atan(to_point.x, -to_point.y);
	float dist = length(to_point);

	// Wiper arc range (roughly -60 to +60 degrees)
	float arc_range = 1.05;
	float sweep_angle = mix(-arc_range, arc_range, wiper_progress);

	// Clear zone: everything the wiper has passed
	float cleared = smoothstep(sweep_angle - 0.05, sweep_angle + 0.05, angle);
	// Only within the wiper's reach radius
	float in_range = step(0.2, dist) * step(dist, 1.0);

	// Wiper blade itself (thin line at current position)
	float blade = smoothstep(0.02, 0.0, abs(angle - sweep_angle)) * in_range;

	return (cleared * in_range * wiper_clear) + blade * 0.5;
}


void fragment() {
	if (rain_intensity <= 0.01) {
		// No rain: fully transparent overlay
		COLOR = vec4(0.0);
		return;
	}

	vec2 uv = UV;

	// ── Compute rain effects ────────────────────────────────────────────────
	vec3 streaks = rain_streak(uv, TIME);
	float streak_mask = streaks.x;
	vec2 streak_distort = streaks.yz;

	vec3 droplets = water_droplets(uv);
	float droplet_mask = droplets.x;
	vec2 droplet_distort = droplets.yz;

	// ── Wiper clearing ──────────────────────────────────────────────────────
	float wiper = wiper_mask(uv);
	float clear_factor = 1.0 - wiper;

	// ── Combined distortion ─────────────────────────────────────────────────
	vec2 total_distort = (streak_distort + droplet_distort) * clear_factor;

	// Sample screen with distortion for refraction effect
	vec2 distorted_uv = SCREEN_UV + total_distort;
	vec4 screen_color = texture(screen_texture, distorted_uv);

	// ── Composite ───────────────────────────────────────────────────────────
	float combined_mask = (streak_mask + droplet_mask * 0.5) * clear_factor;
	combined_mask = clamp(combined_mask, 0.0, 1.0);

	// Rain overlay: tinted translucent layer where water is
	vec3 rain_color = mix(screen_color.rgb, rain_tint.rgb, combined_mask * 0.15);

	// Add subtle highlight to streaks (light catching water)
	float highlight = streak_mask * 0.08 * rain_intensity;
	rain_color += vec3(highlight);

	// Alpha: visible only where there are streaks/droplets
	float alpha = combined_mask * rain_intensity * 0.25;

	// Edge darkening for water pooling at screen edges
	float edge_dark = smoothstep(0.0, 0.15, min(uv.y, 1.0 - uv.y));
	alpha *= edge_dark;

	COLOR = vec4(rain_color, alpha);
}
