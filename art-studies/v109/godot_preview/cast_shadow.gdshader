shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D silhouette_atlas : filter_linear_mipmap, repeat_disable;
uniform float opacity : hint_range(0.0, 0.4) = 0.22;
uniform vec4 shadow_color : source_color = vec4(0.065, 0.087, 0.075, 1.0);
uniform vec4 atlas_region = vec4(0.0, 0.0, 0.25, 0.46875);
uniform float foot_uv_y = 0.458;
uniform float body_uv_height = 0.43945;

float source_alpha(vec2 uv) {
	vec2 inside_min = step(atlas_region.xy, uv);
	vec2 inside_max = step(uv, atlas_region.zw);
	return texture(silhouette_atlas, clamp(uv, atlas_region.xy, atlas_region.zw)).a * inside_min.x * inside_min.y * inside_max.x * inside_max.y;
}

void fragment() {
	float height = clamp((foot_uv_y - UV.y) / body_uv_height, 0.0, 1.0);
	// Softer towards the far end; the source RGB never enters the shadow.
	vec2 blur = TEXTURE_PIXEL_SIZE * mix(7.0, 13.0, height);
	float a = source_alpha(UV) * 0.25;
	a += (source_alpha(UV + vec2(blur.x, 0.0)) + source_alpha(UV - vec2(blur.x, 0.0)) + source_alpha(UV + vec2(0.0, blur.y)) + source_alpha(UV - vec2(0.0, blur.y))) * 0.125;
	a += (source_alpha(UV + blur) + source_alpha(UV - blur) + source_alpha(UV + vec2(blur.x, -blur.y)) + source_alpha(UV + vec2(-blur.x, blur.y))) * 0.0625;
	COLOR = vec4(shadow_color.rgb, a * opacity * mix(1.0, 0.64, height));
}
