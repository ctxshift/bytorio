uniform sampler2D colorSource;
uniform sampler2D depthSource;
uniform sampler2D hudSource;
uniform ivec2 logicalSize;
uniform vec2 residual;
uniform int scale;
uniform int useSmooth;
uniform int useHud;
uniform int sourceBorder;
uniform vec4 background;
uniform int flipY;
uniform int outputHeight;
layout(location = 0) out vec4 colorResult;
void main() {
    ivec2 outputPixel = ivec2(gl_FragCoord.xy);
    if (flipY != 0) outputPixel.y = outputHeight - 1 - outputPixel.y;
    ivec2 logical = outputPixel / scale;
    if (useHud != 0 && texelFetch(hudSource, logical, 0).r > 0.0) {
        colorResult = texelFetch(depthSource, logical, 0);
        return;
    }
    ivec2 world = logical + sourceBorder;
    if (useSmooth != 0) world = ivec2(floor((vec2(outputPixel) + 0.5) / float(scale) + float(sourceBorder) + residual));
    vec4 c = texelFetch(colorSource, world, 0);
    colorResult = c + background * (1.0 - c.a);
}
