shader_type canvas_item;
// Post-process "PS1 / Lethal Company": mało kolorów + dithering Bayera 4x4.
// Rozdzielczość: natywna (bazowo 1920x1080, project.godot).

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform float color_levels = 20.0;
uniform float dither_strength = 1.0;
uniform float vignette = 0.45;

const float BAYER[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0
);

void fragment() {
	vec3 c = texture(screen_texture, SCREEN_UV).rgb;

	vec2 centered = SCREEN_UV - 0.5;
	c *= 1.0 - vignette * dot(centered, centered) * 2.0;

	int x = int(mod(FRAGCOORD.x, 4.0));
	int y = int(mod(FRAGCOORD.y, 4.0));
	float threshold = BAYER[y * 4 + x] / 16.0 - 0.5;
	c += threshold * dither_strength / color_levels;
	c = floor(c * color_levels + 0.5) / color_levels;

	COLOR = vec4(c, 1.0);
}
