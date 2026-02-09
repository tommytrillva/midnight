shader_type canvas_item;

// Post-processing shader for PS1/PS2 era look.
// Applied as screen-space effect for MIDNIGHT GRIND's retro aesthetic.

uniform float color_depth : hint_range(2.0, 256.0) = 32.0;
uniform float dither_strength : hint_range(0.0, 1.0) = 0.3;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.15;
uniform float scanline_frequency : hint_range(100.0, 800.0) = 320.0;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.3;
uniform float chromatic_aberration : hint_range(0.0, 5.0) = 1.0;
uniform float saturation_boost : hint_range(0.0, 2.0) = 1.3;
uniform float bloom_threshold : hint_range(0.0, 1.0) = 0.7;
uniform float bloom_strength : hint_range(0.0, 1.0) = 0.2;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

// 4x4 Bayer dither matrix
const mat4 DITHER_MATRIX = mat4(
	vec4(0.0, 8.0, 2.0, 10.0),
	vec4(12.0, 4.0, 14.0, 6.0),
	vec4(3.0, 11.0, 1.0, 9.0),
	vec4(15.0, 7.0, 13.0, 5.0)
) / 16.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 pixel_size = SCREEN_PIXEL_SIZE;

	// Chromatic aberration
	float ca_offset = chromatic_aberration * pixel_size.x;
	float r = texture(screen_texture, vec2(uv.x + ca_offset, uv.y)).r;
	float g = texture(screen_texture, uv).g;
	float b = texture(screen_texture, vec2(uv.x - ca_offset, uv.y)).b;
	vec3 color = vec3(r, g, b);

	// Saturation boost (for that PS2-era vivid look)
	float luma = dot(color, vec3(0.299, 0.587, 0.114));
	color = mix(vec3(luma), color, saturation_boost);

	// Simple bloom (threshold + blur approximation)
	if (bloom_strength > 0.0) {
		vec3 bloom = vec3(0.0);
		float total = 0.0;
		for (int x = -2; x <= 2; x++) {
			for (int y = -2; y <= 2; y++) {
				vec3 s = texture(screen_texture, uv + vec2(float(x), float(y)) * pixel_size * 3.0).rgb;
				float brightness = max(s.r, max(s.g, s.b));
				if (brightness > bloom_threshold) {
					bloom += s;
					total += 1.0;
				}
			}
		}
		if (total > 0.0) {
			bloom /= total;
			color += bloom * bloom_strength;
		}
	}

	// Color depth reduction (posterization)
	color = floor(color * color_depth + 0.5) / color_depth;

	// Ordered dithering
	if (dither_strength > 0.0) {
		int x = int(mod(FRAGCOORD.x, 4.0));
		int y = int(mod(FRAGCOORD.y, 4.0));
		float threshold = DITHER_MATRIX[y][x];
		float step_size = 1.0 / color_depth;
		color += (threshold - 0.5) * step_size * dither_strength;
	}

	// Scanlines
	if (scanline_strength > 0.0) {
		float scanline = sin(FRAGCOORD.y * 3.14159 / (SCREEN_PIXEL_SIZE.y * scanline_frequency));
		scanline = scanline * scanline;
		color *= 1.0 - scanline * scanline_strength;
	}

	// Vignette
	if (vignette_strength > 0.0) {
		vec2 vig_uv = uv * (1.0 - uv);
		float vig = vig_uv.x * vig_uv.y * 15.0;
		vig = pow(vig, 0.25);
		color *= mix(1.0, vig, vignette_strength);
	}

	COLOR = vec4(clamp(color, 0.0, 1.0), 1.0);
}
