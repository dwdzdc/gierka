shader_type canvas_item;
// Post-process "PS1 / Lethal Company": mało kolorów + dithering Bayera 4x4.
// Rozdzielczość: natywna (bazowo 1920x1080, project.godot).

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform float color_levels = 20.0;
uniform float dither_strength = 1.0;
uniform float vignette = 0.45;
// 0..1: potwór blisko w kadrze (fx/monster_glitch.gd). Rwanie pasów, rozjazd RGB, bloki.
uniform float glitch = 0.0;
// Tłumik efektu: ma być poszlaką („coś tu jest”), a nie utrudnieniem w ucieczce.
// Cała siła zakłócenia mnoży się przez to jedno pokrętło (1.0 = wersja sprzed 1.11).
uniform float glitch_strength = 0.3;

const float BAYER[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0
);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 c;
	if (glitch > 0.001) {
		// Zmienia się skokowo kilkanaście razy na sekundę, nie płynnie: wygląda jak zakłócenie.
		float g = glitch * glitch_strength;
		// Środek kadru zostaje czytelny (tam biegniesz i patrzysz na potwora); przeszkadza
		// tylko brzeg ekranu. Bez tego efekt utrudniał ucieczkę, a to ma być poszlaka.
		float edge = smoothstep(0.18, 0.62, length(SCREEN_UV - vec2(0.5)));
		g *= mix(0.15, 1.0, edge);
		float tick = floor(TIME * 14.0);
		float band = floor(uv.y * 24.0);
		if (hash(vec2(band, tick)) < g * 0.6) {
			uv.x += (hash(vec2(tick, band)) - 0.5) * 0.12 * g;
		}
		vec2 block = floor(uv * vec2(16.0, 9.0));
		bool noisy = hash(block + tick) < g * g * 0.02;
		float split = 0.006 * g;
		c.r = texture(screen_texture, uv + vec2(split, 0.0)).r;
		c.g = texture(screen_texture, uv).g;
		c.b = texture(screen_texture, uv - vec2(split, 0.0)).b;
		if (noisy) {
			c = vec3(hash(FRAGCOORD.xy + tick)) * 0.35;
		}
	} else {
		c = texture(screen_texture, uv).rgb;
	}

	vec2 centered = SCREEN_UV - 0.5;
	c *= 1.0 - vignette * dot(centered, centered) * 2.0;

	int x = int(mod(FRAGCOORD.x, 4.0));
	int y = int(mod(FRAGCOORD.y, 4.0));
	float threshold = BAYER[y * 4 + x] / 16.0 - 0.5;
	c += threshold * dither_strength / color_levels;
	c = floor(c * color_levels + 0.5) / color_levels;

	COLOR = vec4(c, 1.0);
}
