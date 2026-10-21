layout(location = 0) in vec4 position;
layout(location = 1) in vec3 color;
layout(location = 2) in vec2 uv;
out vec3 vertexColor;
out vec2 vertexUV;
uniform vec2 logicalSize;
uniform int border;
void main() {
    // Texture row zero is the console's top row on both hosts.
    gl_Position = vec4(position.x, -position.y, 2.0 * position.z - position.w, position.w);
    gl_Position.xy *= logicalSize / (logicalSize + vec2(float(border * 2)));
    vertexColor = color / 255.0;
    vertexUV = uv;
}
