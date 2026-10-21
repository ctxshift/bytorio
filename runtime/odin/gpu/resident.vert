layout(location = 0) in vec3 position;
layout(location = 1) in vec3 color;
layout(location = 2) in vec3 edgeA;
layout(location = 3) in vec3 edgeB;
layout(location = 4) in vec2 uv;
uniform mat4 model;
uniform mat4 view;
uniform vec3 light;
uniform float ambient;
uniform vec2 logicalSize;
uniform int border;
uniform bool surfaceSamples;
out vec3 vertexColor;
out vec2 vertexUV;
const float SAMPLES_PER_AXIS = 2.0;
const float SPLAT_OVERLAP = 1.4;
void main() {
    vec3 localPosition = position;
    if (surfaceSamples) {
        // Four fixed object-local samples per unit patch, spaced at 0.5 units.
        int sampleIndex = gl_InstanceID & 3;
        vec2 cell = vec2(float(sampleIndex & 1), float(sampleIndex >> 1));
        vec2 uv = (cell + 0.5) / SAMPLES_PER_AXIS;
        localPosition += edgeA * uv.x + edgeB * uv.y;
    }
    vec4 p = view * (model * vec4(localPosition, 1.0));
    gl_Position = vec4(p.x, -p.y, 2.0 * p.z - p.w, p.w);
    vec3 normal = cross(mat3(model) * edgeA, mat3(model) * edgeB);
    if (surfaceSamples) {
        vec2 pixel = floor((gl_Position.xy / p.w * 0.5 + 0.5) * logicalSize) + 0.5;
        gl_Position.xy = (pixel / logicalSize * 2.0 - 1.0) * p.w;
        vec2 a = (view * model * vec4(edgeA, 0.0)).xy * logicalSize * 0.5 / p.w;
        vec2 b = (view * model * vec4(edgeB, 0.0)).xy * logicalSize * 0.5 / p.w;
        float footprint = max(1.0, max(length(a), length(b)) * SPLAT_OVERLAP / SAMPLES_PER_AXIS);
        vec2 corner = vec2(float(gl_VertexID & 1), float(gl_VertexID >> 1)) - 0.5;
        gl_Position.xy += corner * footprint * 2.0 / logicalSize * p.w;
        // Square splats use center depth and reject back-facing surface samples.
        if ((mat3(view) * normal).z >= 0.0) gl_Position = vec4(2.0, 2.0, 2.0, 1.0);
    }
    gl_Position.xy *= logicalSize / (logicalSize + vec2(float(border * 2)));
    vertexColor = color;
    vertexUV = uv;
    if (ambient == 1.0) return;
    float lengthSquared = dot(normal, normal);
    float diffuse = lengthSquared > 0.0 ? dot(normal * inversesqrt(lengthSquared), light) : 0.0;
    vertexColor = color * (ambient + (1.0 - ambient) * clamp(diffuse, 0.0, 1.0));
}
