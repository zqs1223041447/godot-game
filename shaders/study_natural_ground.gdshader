shader_type canvas_item;
render_mode unshaded;

uniform sampler2D soil_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D stone_texture : source_color, filter_linear_mipmap, repeat_enable;
// Linear data channels: grass weight, safe stone-route weight, macro variation.
uniform sampler2D mix_mask : filter_linear, repeat_disable;

uniform vec2 ground_origin_world = vec2(42.0, 104.0);
uniform vec2 ground_bounds_size = vec2(3600.0, 2400.0);
// Includes the study projection once; these are world units, not screen pixels.
uniform vec2 world_units_per_ground_metre = vec2(72.9344729345, 59.7444226034);
uniform float soil_repeats_per_ground_metre = 0.31;
uniform float grass_repeats_per_ground_metre = 0.085;
uniform float grass_secondary_repeats_per_ground_metre = 0.063;
uniform float stone_repeats_per_ground_metre = 0.50;

varying vec2 ground_local_vertex;

void vertex() {
	// Capture the retained quad before canvas/camera transforms. No screen UVs.
	ground_local_vertex = VERTEX;
}

void fragment() {
	vec2 from_origin = ground_local_vertex - ground_origin_world;
	vec2 mask_uv = clamp(from_origin / ground_bounds_size, vec2(0.0), vec2(1.0));
	vec3 weights = texture(mix_mask, mask_uv).rgb;
	vec2 ground_metres = from_origin / world_units_per_ground_metre;
	// Source materials share a fixed XY ground orientation; Godot Y points down.
	ground_metres.y = -ground_metres.y;

	vec3 soil = texture(soil_texture, ground_metres * soil_repeats_per_ground_metre).rgb;
	vec3 grass_primary = texture(grass_texture, ground_metres * grass_repeats_per_ground_metre).rgb;
	vec3 grass_secondary = texture(grass_texture,
		ground_metres * grass_secondary_repeats_per_ground_metre + vec2(0.371, 0.619)).rgb;
	vec3 stone = texture(stone_texture, ground_metres * stone_repeats_per_ground_metre).rgb;

	soil *= vec3(1.08, 1.06, 0.97);
	vec3 grass = mix(grass_primary, grass_secondary, mix(0.28, 0.52, weights.b));
	grass *= vec3(0.62, 0.86, 0.72);
	stone *= vec3(0.98, 0.94, 0.84);
	vec3 ground = mix(soil, grass, weights.r);
	ground = mix(ground, stone, weights.g);
	ground *= mix(0.94, 1.06, weights.b);
	COLOR = vec4(clamp(ground, vec3(0.0), vec3(1.0)), 1.0);
}
