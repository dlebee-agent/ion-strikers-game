shader_type canvas_item;

uniform vec4 glow : source_color = vec4(0.306, 0.886, 0.961, 0.28);

void fragment() {
	vec2 p = (UV - vec2(0.5, 0.55)) * vec2(1.05, 2.4);
	float a = 1.0 - smoothstep(0.0, 0.72, length(p));
	COLOR = vec4(glow.rgb, glow.a * a);
}
