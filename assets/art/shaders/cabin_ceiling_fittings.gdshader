shader_type spatial;
render_mode unshaded;

uniform bool lamp = false;

void fragment() {
	vec2 p = abs(UV * 2.0 - 1.0);
	float edge = max(p.x, p.y);
	vec3 color = vec3(0.026, 0.028, 0.028);
	if (lamp) {
		float lip = max(p.x / 0.94, p.y / 0.76);
		float glass = 1.0 - smoothstep(0.98, 1.0, lip);
		vec2 grille = abs(fract(UV * vec2(28.0, 7.0)) - 0.5);
		float wire = smoothstep(0.44, 0.49, max(grille.x, grille.y));
		float tubes = 0.78 + 0.20 * cos((UV.y - 0.5) * 9.0);
		color *= 0.54 + 0.46 * smoothstep(0.79, 0.99, edge);
		color = mix(color, vec3(1.0, 0.78, 0.49) * (0.61 + tubes * 0.67)
			* mix(1.0, 0.52, wire), glass);
	} else {
		float ring = fract(edge * 8.0);
		float ridge = (1.0 - smoothstep(0.13, 0.48, ring)) * smoothstep(0.1, 0.85, edge);
		vec3 recess = vec3(0.008, 0.009, 0.010) + vec3(0.043, 0.044, 0.043) * ridge;
		recess += vec3(0.009, 0.010, 0.010) * (1.0 - UV.y);
		color = mix(recess, color, smoothstep(0.83, 0.88, edge));
	}
	float bolts = 1.0 - smoothstep(0.027, 0.048, length((p - vec2(0.88, 0.87)) * vec2(lamp ? 3.6 : 1.0, 1.0)));
	ALBEDO = color * (1.0 - bolts * 0.58);
}
