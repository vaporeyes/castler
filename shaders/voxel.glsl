// ABOUTME: Voxel shader. Vertex stage applies the view + projection MVP transform;
// ABOUTME: pixel stage outputs the interpolated per-vertex color (with face shading baked in).

#ifdef VERTEX
varying vec4 vColor;
uniform mat4 u_view;
uniform mat4 u_proj;

// Love2D auto-declares VertexPosition (vec4, w=1 for our 3-float format) and
// VertexColor. We reference them directly rather than redeclaring.
vec4 position(mat4 transform_projection, vec4 vertex_position) {
    vColor = VertexColor;
    return u_proj * u_view * vertex_position;
}
#endif

#ifdef PIXEL
varying vec4 vColor;

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    return vColor;
}
#endif
