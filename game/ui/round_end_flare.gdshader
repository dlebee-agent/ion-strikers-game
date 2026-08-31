shader_type canvas_item;

uniform vec4 glow : source_color = vec4(0.96, 0.27, 0.37, 0.55);

void fragment() {
	vec2 p = UV - vec2(0.5, 0.5);
	float y = p.y * 16.0;
	float x = abs(p.x);
	float core = exp(-y * y * 22.0) * (1.0 - smoothstep(0.10, 0.68, x));
	float bloom = exp(-y * y * 2.4) * (1.0 - smoothstep(0.0, 0.96, x)) * 0.42;
	float streak = exp(-abs(y) * 48.0) * (1.0 - smoothstep(0.04, 0.52, x)) * 0.9;
	COLOR = vec4(glow.rgb, glow.a * (core + bloom + streak));
}
