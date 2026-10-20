uniform sampler2D colorSource;
uniform sampler2D depthSource;
uniform int factor;
uniform int border;
layout(location = 0) out vec4 colorResult;
layout(location = 1) out vec4 depthResult;
void main() {
    ivec2 at = clamp(ivec2(gl_FragCoord.xy) / factor - ivec2(border), ivec2(0), textureSize(colorSource, 0) - 1);
    colorResult = texelFetch(colorSource, at, 0);
    depthResult = texelFetch(depthSource, at, 0);
    uvec4 bytes = uvec4(round(depthResult * 255.0));
    uint bits = bytes.x | (bytes.y << 8) | (bytes.z << 16) | (bytes.w << 24);
    gl_FragDepth = uintBitsToFloat(bits);
}
