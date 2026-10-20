layout(location = 0) in vec3 position;
layout(location = 1) in vec3 color;
layout(location = 2) in vec3 edgeA;
layout(location = 3) in vec3 edgeB;
uniform mat4 model;
uniform mat4 view;
uniform vec3 light;
uniform float ambient;
uniform vec2 logicalSize;
uniform int border;
out vec3 vertexColor;
void main() {
    vec4 p = view * (model * vec4(position, 1.0));
    gl_Position = vec4(p.x, -p.y, 2.0 * p.z - p.w, p.w);
    gl_Position.xy *= logicalSize / (logicalSize + vec2(float(border * 2)));
    vertexColor = color;
    if (ambient == 1.0) return;
    vec3 normal = cross(mat3(model) * edgeA, mat3(model) * edgeB);
    float lengthSquared = dot(normal, normal);
    float diffuse = lengthSquared > 0.0 ? dot(normal * inversesqrt(lengthSquared), light) : 0.0;
    vertexColor = color * (ambient + (1.0 - ambient) * clamp(diffuse, 0.0, 1.0));
}
