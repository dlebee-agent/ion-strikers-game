shader_type canvas_item;

void fragment() {
	vec2 vp = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 px = FRAGCOORD.xy;
	vec2 center = vec2(vp.x * 0.30, vp.y * -0.18);
	vec2 d = (px - center) / vec2(1000.0, 560.0);
	float t = length(d);

	vec3 c0 = vec3(0.137, 0.067, 0.227);
	vec3 c1 = vec3(0.075, 0.047, 0.133);
	vec3 c2 = vec3(0.031, 0.024, 0.059);
	vec3 c3 = vec3(0.020, 0.016, 0.039);

	vec3 col;
	if (t < 0.42) {
		col = mix(c0, c1, t / 0.42);
	} else if (t < 0.74) {
		col = mix(c1, c2, (t - 0.42) / 0.32);
	} else {
		col = mix(c2, c3, clamp((t - 0.74) / 0.26, 0.0, 1.0));
	}
	COLOR = vec4(col, 1.0);
}
