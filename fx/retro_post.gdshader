shader_type canvas_item;
// Post-process "PS1 / Lethal Company": mało kolorów + dithering Bayera 4x4.
// Rozdzielczość: natywna (bazowo 1920x1080, project.godot).

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform float color_levels = 20.0;
uniform float dither_strength = 1.0;
uniform float vignette = 0.45;
// 0..1: potwór blisko w kadrze (fx/monster_glitch.gd). Drżenie obrazu, rwanie pasów, rozjazd RGB, śnieg.
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

// Parametry zakłócenia (glitch). Nazwy, żeby strojenie nie było szukaniem liczb w kodzie.
const float GLITCH_MIN = 0.001;         // poniżej tego efekt wyłączony
const float GLITCH_TICK_HZ = 14.0;      // skoki kilkanaście razy na sekundę
const float GLITCH_BANDS = 24.0;        // pasy poziome
const float GLITCH_BAND_CHANCE = 0.5;   // szansa, że dany pas się przesunie
const float GLITCH_BAND_SHIFT = 0.08;   // maksymalne przesunięcie pasa (UV)
const float GLITCH_RGB_SPLIT = 0.005;   // rozjazd kanałów RGB
const float GLITCH_JITTER_PX = 6.0;     // drżenie całego obrazu: do ±3 px przy pełnej sile
const float GLITCH_SNOW_GRAIN = 2.0;    // ziarno śniegu w pikselach
const float GLITCH_SNOW = 0.45;         // ile śniegu przy pełnej sile
const float GLITCH_SNOW_MAX = 0.7;
const float GLITCH_ROLL = 0.25;         // dodatkowy śnieg w przewijającym się pasie
const float GLITCH_ROLL_WIDTH = 0.03;   // szerokość pasa (UV)
const float GLITCH_ROLL_SPEED = 0.35;   // przesuw pasa na sekundę (UV)
const float GLITCH_EDGE_START = 0.18;   // środek kadru: mało efektu...
const float GLITCH_EDGE_END = 0.62;     // ...krawędź: pełna siła
const float GLITCH_CENTER_MIN = 0.15;   // ile siły zostaje w środku
// Vignette, dithering i hash.
const float VIGNETTE_POWER = 2.0;
const float DITHER_GRID = 4.0;
const int BAYER_SIZE = 4;  // macierz Bayera 4x4
const float DITHER_BIAS = 0.5;
const float BAYER_LEVELS = 16.0;
const vec2 HASH_A = vec2(12.9898, 78.233);
const float HASH_B = 43758.5453;

float hash(vec2 p) {
	return fract(sin(dot(p, HASH_A)) * HASH_B);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 c;
	if (glitch > GLITCH_MIN) {
		// Zmienia się skokowo kilkanaście razy na sekundę, nie płynnie: wygląda jak zakłócenie.
		float tick = floor(TIME * GLITCH_TICK_HZ);
		// Drżenie całego obrazu o 1–3 px (w shaderze, nie ruchem kamery): prawdziwy wstrząs
		// kamery zostaje sygnałem trafienia, więc bliski potwór nie może go udawać. Liczone
		// bez osłabienia środka: cały obraz musi przesunąć się o tyle samo, inaczej się wykrzywia.
		vec2 px = 1.0 / vec2(textureSize(screen_texture, 0));
		uv += (vec2(hash(vec2(tick, 1.7)), hash(vec2(tick, 4.3))) - 0.5) * px * GLITCH_JITTER_PX * glitch * glitch_strength;
		float g = glitch * glitch_strength;
		// Środek kadru zostaje czytelny (tam biegniesz i patrzysz na potwora); przeszkadza
		// tylko brzeg ekranu. Bez tego efekt utrudniał ucieczkę, a to ma być poszlaka.
		float edge = smoothstep(GLITCH_EDGE_START, GLITCH_EDGE_END, length(SCREEN_UV - vec2(0.5)));
		g *= mix(GLITCH_CENTER_MIN, 1.0, edge);
		float band = floor(uv.y * GLITCH_BANDS);
		if (hash(vec2(band, tick)) < g * GLITCH_BAND_CHANCE) {
			uv.x += (hash(vec2(tick, band)) - 0.5) * GLITCH_BAND_SHIFT * g;
		}
		float split = GLITCH_RGB_SPLIT * g;
		c.r = texture(screen_texture, uv + vec2(split, 0.0)).r;
		c.g = texture(screen_texture, uv).g;
		c.b = texture(screen_texture, uv - vec2(split, 0.0)).b;
		// Śnieg jak w starym telewizorze zamiast bloków szumu: drobne ziarno na całym obrazie,
		// gęstsze im bliżej potwór, plus jasny pas przewijający się w dół.
		float snow = hash(floor(FRAGCOORD.xy / GLITCH_SNOW_GRAIN) + vec2(tick * 7.1, tick * 3.3));
		float roll = smoothstep(GLITCH_ROLL_WIDTH, 0.0, abs(fract(SCREEN_UV.y - TIME * GLITCH_ROLL_SPEED) - 0.5));
		c = mix(c, vec3(snow), clamp(g * GLITCH_SNOW + roll * g * GLITCH_ROLL, 0.0, GLITCH_SNOW_MAX));
	} else {
		c = texture(screen_texture, uv).rgb;
	}

	vec2 centered = SCREEN_UV - 0.5;
	c *= 1.0 - vignette * dot(centered, centered) * VIGNETTE_POWER;

	int x = int(mod(FRAGCOORD.x, DITHER_GRID));
	int y = int(mod(FRAGCOORD.y, DITHER_GRID));
	float threshold = BAYER[y * BAYER_SIZE + x] / BAYER_LEVELS - DITHER_BIAS;
	c += threshold * dither_strength / color_levels;
	c = floor(c * color_levels + DITHER_BIAS) / color_levels;

	COLOR = vec4(c, 1.0);
}
