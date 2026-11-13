shader_type spatial;
render_mode unshaded;

// 舱顶平面自带轻微的钢板接缝、紧固件与灯罩溢光。
uniform sampler2D logo_ink : source_color, filter_linear_mipmap, repeat_disable;

float grain(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 p = (UV - 0.5) * 3.38;
	vec2 sheet = fract((p + vec2(0.02, 0.35)) / vec2(1.16, 1.54));
	vec2 edge = min(sheet, 1.0 - sheet);
	float seam = smoothstep(0.001, 0.004, min(edge.x, edge.y));
	float rim = (1.0 - smoothstep(0.005, 0.013, min(edge.x, edge.y))) * seam;
	float bolt = 1.0 - smoothstep(0.009, 0.015, length(edge - vec2(0.034, 0.028)));
	float wear = grain(floor(UV * 720.0)) * 0.003
		+ sin(p.x * 32.0 + sin(p.y * 6.0)) * 0.001
		+ sin(p.x * 4.0 + p.y * 9.0) * 0.002;
	vec2 lamp_offset = max(abs(p - vec2(0.58, 0.49)) - vec2(0.075, 0.46), vec2(0.0));
	float glow = exp(-length(lamp_offset * vec2(8.0, 5.5))) * 0.029;
	float edge_shade = 1.0 - 0.42 * smoothstep(0.86, 1.69, max(abs(p.x), abs(p.y)));
	vec3 steel = (vec3(0.022, 0.026, 0.029) + wear) * edge_shade
		+ vec3(1.0, 0.72, 0.45) * glow + rim * 0.004;
	steel *= mix(0.47, 1.0, seam) * (1.0 - bolt * 0.41);
	vec2 ink_uv = (p - vec2(-0.53, 0.03)) / vec2(0.83, 0.279) + 0.5;
	if (all(greaterThanEqual(ink_uv, vec2(0.0))) && all(lessThanEqual(ink_uv, vec2(1.0)))) {
		vec4 ink = texture(logo_ink, ink_uv);
		steel = mix(steel, steel * 0.13 + ink.rgb * 0.12, ink.a * 0.94);
	}
	ALBEDO = steel;
}
