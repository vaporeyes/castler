// ABOUTME: Voxel shader. Vertex stage applies the view + projection MVP transform
// ABOUTME: and passes view-space depth; pixel stage outputs the vertex color
// ABOUTME: blended toward fog color over distance for DOOM-style depth shading.

#ifdef VERTEX
varying vec4 vColor;
varying float vViewDist;
uniform mat4 u_view;
uniform mat4 u_proj;

vec4 position(mat4 transform_projection, vec4 vertex_position) {
    vColor = VertexColor;
    // Love2D auto-declares VertexPosition as vec4 (w padded to 1 for our
    // 3-float format) and builds vertex_position from it. We use that
    // parameter directly rather than reconstructing the vec4.
    vec4 viewPos = u_view * vertex_position;
    // In OpenGL view space the camera looks toward -Z, so positive distance
    // in front of the eye is -viewPos.z.
    vViewDist = -viewPos.z;
    return u_proj * viewPos;
}
#endif

#ifdef PIXEL
varying vec4 vColor;
varying float vViewDist;
uniform vec3  u_fogColor;
uniform float u_fogStart;
uniform float u_fogEnd;
uniform float u_fogEnabled; // 1.0 = fog on, 0.0 = off (used by overlay meshes)

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    float t = clamp((vViewDist - u_fogStart) / (u_fogEnd - u_fogStart), 0.0, 1.0);
    t = t * u_fogEnabled;
    vec3 final = mix(vColor.rgb, u_fogColor, t);
    return vec4(final, vColor.a);
}
#endif
