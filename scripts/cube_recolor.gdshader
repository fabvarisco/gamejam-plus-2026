shader_type canvas_item;

// Recolors the purple cube sprites to a player's solid color. Past the seam, `glitch`
// slices the sprite and swaps bands to a wrong fill.

uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 glitch_tint : source_color = vec4(1.0);
uniform float glitch = 0.0;
uniform float slice_seed = 0.0;

float hash(float n) {
	return fract(sin(n * 91.7 + slice_seed * 13.37) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	float band = floor(uv.y * 8.0);
	float h = hash(band);
	if (glitch > 0.0 && h < glitch * 0.5) {
		uv.x += (h - 0.25) * 0.25 * glitch;
	}
	vec4 src = texture(TEXTURE, uv);
	float lum = dot(src.rgb, vec3(0.3, 0.5, 0.2));
	float shade = 0.3 + lum * 1.25;
	vec3 base = tint.rgb * shade;
	vec3 wrong = glitch_tint.rgb * shade;
	float swap = step(0.55, hash(band + 7.0)) * glitch;
	COLOR = vec4(mix(base, wrong, clamp(swap, 0.0, 1.0)), src.a * COLOR.a);
}
