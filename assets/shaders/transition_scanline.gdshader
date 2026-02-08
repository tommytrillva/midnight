shader_type canvas_item;

// Scanline sweep transition — CRT retro feel.
// progress 0.0 = fully visible, 1.0 = fully hidden behind scanlines.
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float line_count : hint_range(20.0, 200.0) = 80.0;
uniform float line_thickness : hint_range(0.1, 0.9) = 0.55;
uniform vec4 line_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 glow_color : source_color = vec4(0.0, 1.0, 1.0, 0.3);

void fragment() {
	vec4 original = texture(TEXTURE, UV);

	// Sweep position moves top to bottom
	float sweep_pos = mix(-0.15, 1.15, progress);

	// How far this pixel is below the sweep line
	float sweep_dist = UV.y - sweep_pos;

	// Swept region fades in progressively
	float sweep_mask = smoothstep(-0.1, 0.05, -sweep_dist);

	// Scanline pattern: repeating horizontal bars
	float line_uv = fract(UV.y * line_count);
	float scanline = step(line_thickness, line_uv);

	// Combine: within swept area, apply scanlines that block the scene
	float block = sweep_mask * (1.0 - scanline);

	// Glow at the sweep edge
	float edge_dist = abs(sweep_dist);
	float edge_glow = smoothstep(0.08, 0.0, edge_dist) * sweep_mask;

	// Final color
	vec4 result = mix(original, line_color, block);
	result = mix(result, glow_color, edge_glow * 0.6);
	COLOR = result;
}
