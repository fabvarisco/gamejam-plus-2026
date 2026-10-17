shader_type canvas_item;

// Warm, naive sky for the honest half; broken interface gray with a grid past the seam.
// `height` goes 0 to 1 from the village to the top of the mountain.

uniform float corruption : hint_range(0.0, 1.0) = 0.0;
uniform float height : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float y = UV.y;
	vec3 warm_top = mix(vec3(0.98, 0.62, 0.38), vec3(0.42, 0.3, 0.55), height);
	vec3 warm_bottom = mix(vec3(1.0, 0.86, 0.6), vec3(0.95, 0.6, 0.45), height);
	vec3 warm = mix(warm_top, warm_bottom, y);

	vec3 gray = mix(vec3(0.16, 0.17, 0.2), vec3(0.28, 0.29, 0.33), y);
	vec2 cell = fract(FRAGCOORD.xy / 32.0);
	float line = step(cell.x, 0.04) + step(cell.y, 0.04);
	gray += vec3(0.08, 0.1, 0.13) * clamp(line, 0.0, 1.0);
	float scan = step(0.5, fract(FRAGCOORD.y * 0.5)) * 0.03;
	gray -= scan;

	COLOR = vec4(mix(warm, gray, corruption), 1.0);
}
