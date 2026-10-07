shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform float opacity : hint_range(0.0, 0.4) = 0.30;
uniform vec4 shadow_color : source_color = vec4(0.045, 0.062, 0.051, 1.0);

float soft_contact(vec2 point, vec2 centre, vec2 radius) {
	float r = length((point - centre) / radius);
	return 1.0 - smoothstep(0.12, 1.0, r);
}

void fragment() {
	vec2 point = (UV - vec2(0.5)) * vec2(32.0, 12.0);
	float left = soft_contact(point, vec2(-4.8, -0.6), vec2(6.5, 3.0));
	float right = soft_contact(point, vec2(4.6, 0.0), vec2(6.2, 2.9));
	// Two small boot-sized contacts, not a hard black disc under the actor.
	COLOR = vec4(shadow_color.rgb, max(left, right) * opacity);
}
