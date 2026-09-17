shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform vec4 line_color : source_color = vec4(0.38, 0.42, 0.48, 1.0);
uniform vec4 axis_color_x : source_color = vec4(0.75, 0.28, 0.28, 1.0);
uniform vec4 axis_color_z : source_color = vec4(0.28, 0.42, 0.75, 1.0);
uniform vec4 fill_color : source_color = vec4(0.11, 0.12, 0.14, 1.0);
uniform float cell_size = 1.0;
uniform float line_width = 1.5;
uniform float fade_start = 12.0;
uniform float fade_end = 28.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 coord = world_pos.xz / cell_size;
	vec2 derivative = fwidth(coord);
	vec2 grid = abs(fract(coord - 0.5) - 0.5) / derivative;
	float line = min(grid.x, grid.y);
	float grid_alpha = 1.0 - clamp(line / line_width, 0.0, 1.0);

	float axis_x = 1.0 - clamp(abs(world_pos.z) / (derivative.y * cell_size * line_width * 1.6), 0.0, 1.0);
	float axis_z = 1.0 - clamp(abs(world_pos.x) / (derivative.x * cell_size * line_width * 1.6), 0.0, 1.0);

	vec3 color = fill_color.rgb;
	color = mix(color, line_color.rgb, grid_alpha);
	color = mix(color, axis_color_x.rgb, axis_x);
	color = mix(color, axis_color_z.rgb, axis_z);

	float dist = length(world_pos.xz);
	float fade = 1.0 - smoothstep(fade_start, fade_end, dist);
	ALBEDO = mix(fill_color.rgb * 0.35, color, fade);
	ALPHA = 1.0;
}
