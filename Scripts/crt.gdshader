shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float scanline_count : hint_range(0, 1800) = 250.0;
uniform float scan_speed : hint_range(0.0, 10.0) = 2.0;
uniform vec4 tint_color : source_color = vec4(0.1, 0.3, 0.5, 1.0);
uniform float aberration_amount : hint_range(0.0, 0.05) = 0.003;

void fragment() {
	vec2 uv = SCREEN_UV;
	
	// Chromatic Aberration
	float r = texture(screen_texture, uv + vec2(aberration_amount, 0.0)).r;
	float g = texture(screen_texture, uv).g;
	float b = texture(screen_texture, uv - vec2(aberration_amount, 0.0)).b;
	vec4 base_color = vec4(r, g, b, 1.0);
	
	// Scanlines
	float s = sin(uv.y * scanline_count * 3.14159 + TIME * scan_speed);
	float scan_intensity = (s * 0.5 + 0.5) * 0.15 + 0.85;
	
	// Vignette
	float dist = distance(uv, vec2(0.5, 0.5));
	float vignette = smoothstep(0.9, 0.3, dist);
	
	// Tactical Tint
	base_color = mix(base_color, tint_color, 0.15);
	
	COLOR = base_color * scan_intensity * vignette;
}
