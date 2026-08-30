shader_type canvas_item;

void fragment() {
	float a = mod(FRAGCOORD.y, 4.0) < 1.0 ? 0.014 : 0.0;
	COLOR = vec4(1.0, 1.0, 1.0, a);
}
