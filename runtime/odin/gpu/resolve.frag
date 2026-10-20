uniform sampler2D colorSource;
uniform sampler2D depthSource;
uniform int factor;
layout(location = 0) out vec4 colorResult;
layout(location = 1) out vec4 depthResult;
vec3 decode(vec3 c) {
    return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), greaterThan(c, vec3(0.04045)));
}
vec3 encode(vec3 c) {
    return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, greaterThan(c, vec3(0.0031308)));
}
void main() {
    ivec2 base = ivec2(gl_FragCoord.xy) * factor;
    vec4 sum = vec4(0.0);
    float nearest = 1.0;
    for (int y = 0; y < 6; y++) {
        for (int x = 0; x < 6; x++) {
            if (x >= factor || y >= factor) continue;
            vec4 c = texelFetch(colorSource, base + ivec2(x, y), 0);
            sum += vec4(decode(c.rgb / max(c.a, 0.00001)) * c.a, c.a);
            uvec4 b = uvec4(round(texelFetch(depthSource, base + ivec2(x, y), 0) * 255.0));
            nearest = min(nearest, uintBitsToFloat(b.x | (b.y << 8) | (b.z << 16) | (b.w << 24)));
        }
    }
    sum /= float(factor * factor);
    colorResult = vec4(encode(sum.rgb / max(sum.a, 0.00001)) * sum.a, sum.a);
    uint bits = floatBitsToUint(nearest);
    depthResult = vec4(uvec4(bits, bits >> 8, bits >> 16, bits >> 24) & 255u) / 255.0;
}
