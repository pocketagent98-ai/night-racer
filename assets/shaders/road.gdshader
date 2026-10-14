shader_type spatial;
render_mode cull_disabled;

// Scrolling road. UV repeat is forced with the `repeat_enable` sampler hint
// so the texture tiles along the whole length of the road plane.
uniform sampler2D road_tex : repeat_enable, filter_linear_mipmap;
uniform vec2 uv_scale = vec2(1.0, 40.0);
uniform vec2 uv_offset = vec2(0.0, 0.0);

void fragment() {
	vec2 uv = UV * uv_scale + uv_offset;
	vec3 c = texture(road_tex, uv).rgb;
	ALBEDO = c;
	ROUGHNESS = 0.9;
	METALLIC = 0.0;
}
