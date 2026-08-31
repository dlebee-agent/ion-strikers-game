shader_type sky;

uniform samplerCube sky_cube : filter_linear, source_color, hint_default_black;
uniform float exposure : hint_range(0, 8) = 1.0;

void sky() {
	COLOR = texture(sky_cube, EYEDIR).rgb * exposure;
}
