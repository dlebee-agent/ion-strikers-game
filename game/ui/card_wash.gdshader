shader_type canvas_item;

uniform vec4 wash : source_color = vec4(0.306, 0.886, 0.961, 0.18);

void fragment() {
	float t = clamp((UV.x * 0.4 + UV.y) / 0.65, 0.0, 1.0);
	COLOR = vec4(wash.rgb, wash.a * mix(1.0, 0.11, t));
}
