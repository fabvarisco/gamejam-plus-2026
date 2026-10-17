shader_type canvas_item;

// Screen glitches past the seam: horizontal tears, RGB split, blocks of missed pixels,
// and time that advances in stuck steps.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float t = floor(TIME * 9.0);
	float band = floor(uv.y * 22.0);
	float r = hash(vec2(band, t));
	if (r < intensity * 0.3) {
		uv.x += (hash(vec2(band, t + 1.0)) - 0.5) * 0.12 * intensity;
	}
	float split = 0.006 * intensity;
	vec3 col;
	col.r = texture(screen_tex, uv + vec2(split, 0.0)).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - vec2(split, 0.0)).b;
	// Missed pixels only during bursts; the steady state just tears and splits.
	vec2 block = floor(uv * vec2(64.0, 36.0));
	float b = hash(block + t);
	if (b < max(intensity - 0.3, 0.0) * 0.03) {
		col = hash(block + t + 3.0) > 0.5 ? vec3(0.95, 0.2, 0.75) : vec3(0.08);
	}
	COLOR = vec4(col, 1.0);
}
