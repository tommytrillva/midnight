shader_type canvas_item;

// Horizontal wipe transition with a neon-cyan leading edge.
// progress 0.0 = fully visible, 1.0 = fully wiped to black.
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec2 direction = vec2(1.0, 0.0);
uniform float edge_width : hint_range(0.001, 0.1) = 0.015;
uniform vec4 edge_color : source_color = vec4(0.0, 1.0, 1.0, 1.0);

void fragment() {
	// Normalize direction
	vec2 dir = normalize(direction);

	// Project UV onto direction vector (0..1 range)
	float projected = dot(UV - vec2(0.5), dir) + 0.5;

	// Wipe threshold moves from -edge_width to 1+edge_width
	float threshold = mix(-edge_width, 1.0 + edge_width, progress);

	// Distance from the wipe edge
	float dist = projected - threshold;

	// Hard wipe: everything behind threshold is black
	float wipe_mask = step(0.0, dist);

	// Neon leading edge glow
	float edge_glow = 1.0 - smoothstep(0.0, edge_width, abs(dist));
	edge_glow *= edge_glow; // Sharpen the glow

	// Sample original texture
	vec4 original = texture(TEXTURE, UV);

	// Mix: wiped area is black, edge glows cyan, rest is original
	vec4 result = mix(vec4(0.0, 0.0, 0.0, 1.0), original, wipe_mask);
	result = mix(result, edge_color, edge_glow * 0.9);
	COLOR = result;
}
