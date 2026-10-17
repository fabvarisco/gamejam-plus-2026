shader_type canvas_item;

// Each room's sky is a flat gradient, with stars at night and in the cave. Past the seam
// it turns to broken interface gray with a grid and scanlines.

uniform float corruption : hint_range(0.0, 1.0) = 0.0;
uniform vec3 top_color : source_color = vec3(0.98, 0.62, 0.38);
uniform vec3 bottom_color : source_color = vec3(1.0, 0.86, 0.6);
uniform float stars : hint_range(0.0, 1.0) = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec3 sky = mix(top_color, bottom_color, UV.y);
	vec2 cell = floor(FRAGCOORD.xy / 6.0);
	float h = hash(cell);
	float star = step(0.993, h) * (0.6 + 0.4 * sin(TIME * 2.0 + h * 50.0)) * (1.0 - UV.y * 0.7);
	sky += vec3(star) * stars;

	vec2 grid = fract(FRAGCOORD.xy / 32.0);
	float line = step(grid.x, 0.04) + step(grid.y, 0.04);
	float scan = step(0.5, fract(FRAGCOORD.y * 0.5)) * 0.03;
	sky += (vec3(0.08, 0.1, 0.13) * clamp(line, 0.0, 1.0) - scan) * corruption;

	COLOR = vec4(sky, 1.0);
}
