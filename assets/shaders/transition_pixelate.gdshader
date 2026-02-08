shader_type canvas_item;

// Pixelation transition shader — PS1/PS2 retro style.
// progress 0.0 = fully clear, 0.5 = maximum pixelation, 1.0 = clear again.
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float max_pixel_size : hint_range(4.0, 128.0) = 64.0;

void fragment() {
	// Convert progress into a triangle wave: 0→1→0 as progress goes 0→0.5→1
	float pixel_factor = 1.0 - abs(2.0 * progress - 1.0);

	// Smooth the curve for a nicer ramp
	pixel_factor = smoothstep(0.0, 1.0, pixel_factor);

	// Calculate pixel size (1.0 = no pixelation, max_pixel_size = full block)
	float pixel_size = mix(1.0, max_pixel_size, pixel_factor);

	// Snap UVs to a pixel grid
	vec2 screen_size = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 grid_size = screen_size / pixel_size;
	vec2 snapped_uv = (floor(UV * grid_size) + 0.5) / grid_size;

	// Fade to black at the midpoint for scene-swap coverage
	float fade = smoothstep(0.4, 0.5, pixel_factor);
	vec4 pixel_color = texture(TEXTURE, snapped_uv);
	COLOR = mix(pixel_color, vec4(0.0, 0.0, 0.0, 1.0), fade);
}
