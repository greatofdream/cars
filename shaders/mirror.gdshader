shader_type canvas_item;

// Convex side-mirror look: widen/curve the flat SubViewport render with a radial
// (barrel) warp, then mask the warped-out corners to transparent so the box frame shows.
uniform sampler2D mirror_tex : filter_linear;
uniform float curvature : hint_range(0.0, 0.8) = 0.28;
uniform bool convex = true;

void fragment() {
	if (!convex) {
		COLOR = texture(mirror_tex, UV);
		return;
	}
	// map from output pixel back into a warped source UV; stronger at the edges
	vec2 c = UV - vec2(0.5);
	float r2 = dot(c, c) * 4.0;          // 0 at center, 1 at edge
	vec2 src = 0.5 + c * (1.0 + curvature * (r2 - 0.5));
	if (src.x < 0.0 || src.x > 1.0 || src.y < 0.0 || src.y > 1.0) {
		COLOR = vec4(0.0, 0.0, 0.0, 0.0);
	} else {
		COLOR = texture(mirror_tex, src);
	}
}
