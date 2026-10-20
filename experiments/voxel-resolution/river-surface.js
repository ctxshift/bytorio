// Fixed object-local samples: identity, position, normal and baked color never
// change with the view. Screen-aligned splats deliberately trade exact silhouettes
// for stable sample colors; they are an experimental representation of the rabbit.
const SAMPLE_SPACING = 0.25;
const RECORD_FLOATS = 9;

export function surfaceSamples(mesh) {
  const view = new DataView(mesh);
  const records = [];
  const position = (vertex) =>
    [0, 1, 2].map((axis) => view.getFloat32(vertex * 16 + axis * 4, true));
  for (let face = 0; face < mesh.byteLength / 96; face++) {
    const a = position(face * 6);
    const b = position(face * 6 + 1);
    const d = position(face * 6 + 5);
    const u = b.map((v, i) => v - a[i]);
    const v = d.map((value, i) => value - a[i]);
    const normal = [
      u[1] * v[2] - u[2] * v[1],
      u[2] * v[0] - u[0] * v[2],
      u[0] * v[1] - u[1] * v[0],
    ];
    const length = Math.hypot(...normal);
    if (!length) {
      continue;
    }
    const color = [0, 1, 2].map((channel) => view.getUint8(face * 96 + 12 + channel) / 255);
    const nx = Math.ceil(Math.hypot(...u) / SAMPLE_SPACING);
    const ny = Math.ceil(Math.hypot(...v) / SAMPLE_SPACING);
    for (let y = 0; y < ny; y++) {
      for (let x = 0; x < nx; x++) {
        records.push(
          ...a.map((value, i) => value + (u[i] * (x + 0.5)) / nx + (v[i] * (y + 0.5)) / ny),
          ...normal.map((value) => value / length),
          ...color,
        );
      }
    }
  }
  return new Float32Array(records);
}

const VERTEX = `#version 300 es
precision highp float;
layout(location=0) in vec3 position;
layout(location=1) in vec3 normal;
layout(location=2) in vec3 color;
uniform vec3 translation, target, right, up, forward;
uniform vec2 span;
uniform float rotation, pixel, factor;
out vec3 linearColor;
vec3 turn(vec3 p) {
  float s=sin(rotation), c=cos(rotation);
  return vec3(p.x*c+p.z*s,p.y,-p.x*s+p.z*c);
}
void main() {
  vec3 p=turn(position)+translation;
  vec2 projected=vec2(dot(p,right)-target.x,dot(p,up)-target.y);
  // The output lattice stays at the selected game resolution even with SSAA.
  projected=(floor(projected/pixel)+0.5)*pixel;
  gl_Position=vec4(projected*2.0/span,(dot(p,forward)-target.z+260.0)/250.0-1.0,1.0);
  if(dot(turn(normal),forward)>=-0.00001) gl_Position=vec4(2.0,2.0,2.0,1.0);
  gl_PointSize=max(1.0,${SAMPLE_SPACING}*1.4/pixel)*factor;
  linearColor=mix(color/12.92,pow((color+0.055)/1.055,vec3(2.4)),greaterThan(color,vec3(0.04045)));
}`;

const FRAGMENT = `#version 300 es
precision highp float;
in vec3 linearColor;
out vec4 result;
void main() { result=vec4(linearColor,1.0); }`;

export class RabbitSurface {
  constructor(gl, program, mesh) {
    this.gl = gl;
    this.samples = surfaceSamples(mesh);
    this.count = this.samples.length / RECORD_FLOATS;
    this.program = program(VERTEX, FRAGMENT);
    this.uniforms = Object.fromEntries(
      [
        "translation",
        "target",
        "right",
        "up",
        "forward",
        "span",
        "rotation",
        "pixel",
        "factor",
      ].map((name) => [name, gl.getUniformLocation(this.program, name)]),
    );
    this.vao = gl.createVertexArray();
    gl.bindVertexArray(this.vao);
    this.buffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, this.buffer);
    gl.bufferData(gl.ARRAY_BUFFER, this.samples, gl.STATIC_DRAW);
    for (let attribute = 0; attribute < 3; attribute++) {
      gl.enableVertexAttribArray(attribute);
      gl.vertexAttribPointer(attribute, 3, gl.FLOAT, false, RECORD_FLOATS * 4, attribute * 12);
    }
  }

  draw(basis, target, rabbit, angle, span, pixel, factor) {
    const gl = this.gl;
    const u = this.uniforms;
    gl.useProgram(this.program);
    for (const name of ["right", "up", "forward"]) {
      gl.uniform3fv(u[name], basis[name]);
    }
    gl.uniform3fv(
      u.target,
      ["right", "up", "forward"].map((name) =>
        target.reduce((sum, value, i) => sum + value * basis[name][i], 0),
      ),
    );
    gl.uniform3fv(u.translation, rabbit);
    gl.uniform1f(u.rotation, angle);
    gl.uniform1f(u.pixel, pixel);
    gl.uniform1f(u.factor, factor);
    gl.uniform2fv(u.span, span);
    gl.bindVertexArray(this.vao);
    gl.drawArrays(gl.POINTS, 0, this.count);
  }
}
