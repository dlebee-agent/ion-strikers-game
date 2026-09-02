shader_type spatial;

// The player suit, painted onto the stock mannequin instead of modelled: seam
// channels along the panel lines, a hexagonal core at the sternum, a full-face
// visor with lit eyes, gloves, boots and a two-tone body. Everything is drawn
// from the mesh's rest-pose position and normal, which SuitMaterial bakes into
// CUSTOM0/CUSTOM1, so the design stays put through animation and the ragdoll.
// The mannequin rests in a T-pose facing +Z with its feet at y=0, so the arms
// run along x and the legs along y in the maths below.

uniform vec3 body_color : source_color = vec3(0.227, 0.565, 1.0);
uniform float body_emission = 0.28;
uniform vec3 seam_color : source_color = vec3(0.03, 0.032, 0.04);
uniform float seam_roughness = 0.12;
uniform vec3 seam_glow : source_color = vec3(1.0);
uniform float seam_glow_energy = 0.0;
uniform vec3 core_color : source_color = vec3(1.0);
uniform float core_energy = 1.8;
uniform float visor_edge_energy = 0.0;
uniform float eye_energy = 4.0;

varying vec3 v_rest;
varying vec3 v_restn;

void vertex() {
	v_rest = CUSTOM0.xyz;
	v_restn = CUSTOM1.xyz;
}

// 1 inside a line of half-width w, softened by one pixel so seams stay crisp
// at any distance without shimmering.
float band(float d, float w) {
	w *= 0.78;
	float aa = fwidth(d) + 0.0005;
	return 1.0 - smoothstep(w - aa, w + aa, d);
}

float segd(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

float rng(float v, float lo, float hi) {
	return step(lo, v) * step(v, hi);
}

float hexd(vec2 p) {
	p = abs(p);
	return max(dot(p, vec2(0.8660254, 0.5)), p.y);
}

void fragment() {
	vec3 P = v_rest;
	vec3 N = normalize(v_restn);
	float front = smoothstep(0.05, 0.35, N.z);
	float back = smoothstep(0.05, 0.35, -N.z);
	float sx = P.x < 0.0 ? -1.0 : 1.0;
	float ax = abs(P.x);
	vec2 pf = vec2(ax, P.y);
	float L = 0.0;

	// Torso, front: twin bars either side of the sternum, a centre column, a
	// collar V, side lines and an abdomen chevron.
	float torso = rng(P.y, 0.90, 1.50) * step(ax, 0.20);
	L = max(L, front * torso * band(segd(pf, vec2(0.052, 1.06), vec2(0.052, 1.43)), 0.0085));
	L = max(L, front * torso * band(segd(pf, vec2(0.0, 0.97), vec2(0.0, 1.27)), 0.0075));
	L = max(L, front * torso * band(segd(pf, vec2(0.165, 1.475), vec2(0.07, 1.37)), 0.0075));
	L = max(L, front * torso * band(segd(pf, vec2(0.128, 1.12), vec2(0.135, 1.40)), 0.0065));
	L = max(L, front * torso * band(segd(pf, vec2(0.115, 0.965), vec2(0.03, 1.03)), 0.0065));

	// Sternum core: a hexagon with a dark bezel ring.
	float core_d = hexd(pf - vec2(0.0, 1.335));
	float core = front * torso * band(core_d, 0.03);
	float bezel = front * torso * band(abs(core_d - 0.042), 0.007);

	// Torso, back: spine and shoulder blades.
	L = max(L, back * torso * band(segd(pf, vec2(0.0, 0.97), vec2(0.0, 1.47)), 0.0085));
	L = max(L, back * torso * band(segd(pf, vec2(0.125, 1.44), vec2(0.05, 1.12)), 0.0065));
	L = max(L, back * torso * band(segd(pf, vec2(0.05, 1.12), vec2(0.12, 0.98)), 0.0065));

	// Arms: stripes along the top and front, rings at shoulder, elbow, wrist.
	float arm = step(0.20, ax) * rng(P.y, 1.22, 1.62);
	float arm_top = smoothstep(0.15, 0.5, N.y);
	float arm_front = smoothstep(0.15, 0.5, N.z);
	L = max(L, arm * arm_top * band(abs(P.z + 0.02), 0.0075) * rng(ax, 0.245, 0.445));
	L = max(L, arm * arm_front * band(abs(P.y - 1.415), 0.0075) * rng(ax, 0.49, 0.71));
	L = max(L, arm * arm_top * band(abs(P.z + 0.02), 0.006) * rng(ax, 0.52, 0.71));
	L = max(L, arm * band(abs(ax - 0.465), 0.0055));
	L = max(L, arm * band(abs(ax - 0.225), 0.0065));
	L = max(L, arm * band(abs(ax - 0.735), 0.0055));
	float glove = step(0.745, ax) * arm;

	// Legs: outer thigh stripe, shin and thigh fronts, knee and ankle rings.
	float leg = rng(P.y, 0.115, 0.92) * step(0.015, ax);
	float outer = smoothstep(0.15, 0.5, N.x * sx);
	float leg_front = smoothstep(0.15, 0.5, N.z);
	L = max(L, leg * outer * band(abs(P.z + 0.005), 0.0075) * rng(P.y, 0.56, 0.87));
	L = max(L, leg * leg_front * band(abs(ax - 0.088), 0.0075) * rng(P.y, 0.16, 0.47));
	L = max(L, leg * leg_front * band(abs(ax - 0.088), 0.0065) * rng(P.y, 0.60, 0.86));
	L = max(L, leg * band(abs(P.y - 0.505), 0.0055));
	L = max(L, leg * band(abs(P.y - 0.135), 0.0055));
	float boot = step(P.y, 0.118);

	// Neck, helmet, visor and eyes.
	float neck = rng(P.y, 1.485, 1.568) * step(ax, 0.13);
	float head = step(1.568, P.y);
	float e = sqrt(pow(ax / 0.09, 2.0) + pow((P.y - 1.695) / 0.078, 2.0));
	float face_facing = smoothstep(0.0, 0.25, N.z);
	float visor = head * (1.0 - smoothstep(0.98, 1.02, e)) * face_facing;
	float visor_edge = head * band(abs(e - 1.0), 0.09) * face_facing;
	L = max(L, head * back * band(ax, 0.006) * step(1.72, P.y));
	L = max(L, head * band(abs(P.y - 1.60), 0.005) * (1.0 - face_facing));
	float eye_d = segd(pf, vec2(0.016, 1.698), vec2(0.05, 1.712));
	float eyes = visor * band(eye_d, 0.0055);
	float eye_glow = visor * (1.0 - smoothstep(0.0, 0.035, eye_d));

	float dark = max(max(glove, boot), max(neck, visor));
	L *= 1.0 - dark;

	// Two-tone: flanks, underarms, inner thighs and calves drop to a deeper shade.
	float flank = smoothstep(0.55, 0.9, abs(N.x)) * torso * step(0.09, ax);
	float under_arm = smoothstep(0.3, 0.7, -N.y) * arm * (1.0 - glove);
	float inner_leg = smoothstep(0.45, 0.85, -N.x * sx) * leg;
	float calf = smoothstep(0.4, 0.8, -N.z) * leg * rng(P.y, 0.14, 0.48);
	float tone = max(max(flank, under_arm), max(inner_leg, calf)) * (1.0 - dark);

	vec3 col = mix(body_color, body_color * 0.5, tone);
	col = mix(col, seam_color, L);
	col = mix(col, vec3(0.012, 0.013, 0.018), dark);
	col = mix(col, vec3(0.02), bezel);
	col = mix(col, vec3(0.0), max(core, eyes));
	ALBEDO = col;

	float rough = mix(0.5, seam_roughness, max(L, bezel));
	rough = mix(rough, 0.16, dark);
	rough = mix(rough, 0.08, visor);
	ROUGHNESS = rough;
	METALLIC = mix(0.12, 0.4, dark);
	SPECULAR = 0.5;
	CLEARCOAT = 0.7;
	CLEARCOAT_ROUGHNESS = 0.28;

	EMISSION = body_color * body_emission * (1.0 - max(L, dark))
		+ seam_glow * seam_glow_energy * max(L, visor_edge * visor_edge_energy)
		+ core_color * core_energy * core
		+ vec3(1.0) * (eyes * eye_energy + eye_glow * 0.35);
}
