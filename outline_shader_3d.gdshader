shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix;

uniform float width : hint_range(0.0, 30.0) = 5.0;
uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 0.0, 1.0);
uniform sampler2D sprite_texture : source_color;

void fragment() {
	float size = width * 1.0 / float(textureSize(sprite_texture, 0).x);

	vec4 sprite_color = texture(sprite_texture, UV);
	float alpha = -8.0 * sprite_color.a;

	alpha += texture(sprite_texture, UV + vec2(0.0, -size)).a;
	alpha += texture(sprite_texture, UV + vec2(size, -size)).a;
	alpha += texture(sprite_texture, UV + vec2(size, 0.0)).a;
	alpha += texture(sprite_texture, UV + vec2(size, size)).a;

	alpha += texture(sprite_texture, UV + vec2(0.0, size)).a;
	alpha += texture(sprite_texture, UV + vec2(-size, size)).a;
	alpha += texture(sprite_texture, UV + vec2(-size, 0.0)).a;
	alpha += texture(sprite_texture, UV + vec2(-size, -size)).a;

	vec4 final_color = mix(sprite_color, outline_color, clamp(alpha, 0.0, 1.0));
	ALBEDO = final_color.rgb;
	ALPHA = clamp(abs(alpha) + sprite_color.a, 0.0, 1.0);
}
