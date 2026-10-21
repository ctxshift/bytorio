in vec3 vertexColor;
in vec2 vertexUV;
uniform bool useTexture;
uniform sampler2D materialTexture;
uniform ivec2 textureAddress;
uniform bool alphaCutout;
uniform int alphaCutoff;
uniform vec3 fogColor;
uniform vec2 fogRange;
layout(location = 0) out vec4 colorResult;
layout(location = 1) out vec4 depthResult;
void main() {
    float fog = clamp((gl_FragCoord.z - fogRange.x) / (fogRange.y - fogRange.x), 0.0, 1.0);
    vec3 tinted = vertexColor;
    if (useTexture) {
        vec2 coordinate = vec2(textureAddress.x == 1 ? fract(vertexUV.x) : clamp(vertexUV.x, 0.0, 1.0),
                               textureAddress.y == 1 ? fract(vertexUV.y) : clamp(vertexUV.y, 0.0, 1.0));
        ivec2 size = textureSize(materialTexture, 0);
        ivec2 texel = min(ivec2(floor(coordinate * vec2(size))), size - 1);
        vec4 sampleColor = texelFetch(materialTexture, texel, 0);
        if (alphaCutout && int(floor(sampleColor.a * 255.0 + 0.5)) < alphaCutoff) discard;
        tinted *= sampleColor.rgb;
        if (alphaCutout) tinted /= max(sampleColor.a, 1.0 / 255.0);
    }
    colorResult = vec4(floor(mix(tinted, fogColor, fog) * 255.0 + 0.5) / 255.0, 1.0);
    uint bits = floatBitsToUint(gl_FragCoord.z);
    depthResult = vec4(uvec4(bits, bits >> 8, bits >> 16, bits >> 24) & 255u) / 255.0;
}
