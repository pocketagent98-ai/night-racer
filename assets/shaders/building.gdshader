shader_type spatial;
render_mode cull_back;

// One material for every skyline block; each instance sets its own window grid
// density through an instance uniform.
instance uniform vec2 uv_scale = vec2(2.0, 6.0);
uniform sampler2D tex : repeat_enable, filter_linear_mipmap;

void fragment() {
	vec3 c = texture(tex, UV * uv_scale).rgb;
	ALBEDO = c;
	EMISSION = c * 1.6;
	ROUGHNESS = 0.95;
	METALLIC = 0.0;
}
