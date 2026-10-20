in vec3 vertexColor;
uniform vec3 fogColor;
uniform vec2 fogRange;
layout(location = 0) out vec4 colorResult;
layout(location = 1) out vec4 depthResult;
void main() {
    float fog = clamp((gl_FragCoord.z - fogRange.x) / (fogRange.y - fogRange.x), 0.0, 1.0);
    colorResult = vec4(floor(mix(vertexColor, fogColor, fog) * 255.0 + 0.5) / 255.0, 1.0);
    uint bits = floatBitsToUint(gl_FragCoord.z);
    depthResult = vec4(uvec4(bits, bits >> 8, bits >> 16, bits >> 24) & 255u) / 255.0;
}
