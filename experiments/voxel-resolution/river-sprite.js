// A single bounded object-local capture. Translation never changes its sampling phase.
const VERTEX = `#version 300 es
void main() {
  vec2 p=vec2(float((gl_VertexID<<1)&2),float(gl_VertexID&2));
  gl_Position=vec4(p*2.0-1.0,0.0,1.0);
}`;
const FRAGMENT = `#version 300 es
precision highp float;
precision highp int;
uniform sampler2D colorSource;
uniform sampler2D depthSource;
uniform int factor;
out vec4 result;
void main() {
  ivec2 base=ivec2(gl_FragCoord.xy)*factor;
  vec4 sum=vec4(0.0);
  float depth=1.0;
  for(int y=0;y<6;y++) for(int x=0;x<6;x++) {
    if(x<factor && y<factor) {
      vec4 c=texelFetch(colorSource,base+ivec2(x,y),0);
      sum+=c;
      if(c.a>0.0) depth=min(depth,texelFetch(depthSource,base+ivec2(x,y),0).r);
    }
  }
  result=sum/float(factor*factor);
  gl_FragDepth=depth;
}`;

export function makeTexture(gl, depth = false) {
  const texture = gl.createTexture();
  gl.bindTexture(gl.TEXTURE_2D, texture);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  if (depth) {
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_COMPARE_MODE, gl.NONE);
  }
  return texture;
}

export function allocateTexture(gl, texture, width, height, depth = false) {
  gl.bindTexture(gl.TEXTURE_2D, texture);
  gl.texImage2D(
    gl.TEXTURE_2D,
    0,
    depth ? gl.DEPTH_COMPONENT24 : gl.RGBA8,
    width,
    height,
    0,
    depth ? gl.DEPTH_COMPONENT : gl.RGBA,
    depth ? gl.UNSIGNED_INT : gl.UNSIGNED_BYTE,
    null,
  );
}

export class RabbitSprite {
  constructor(gl, program) {
    this.gl = gl;
    this.program = program(VERTEX, FRAGMENT);
    this.high = {
      framebuffer: gl.createFramebuffer(),
      color: makeTexture(gl),
      depth: makeTexture(gl, true),
    };
    this.low = {
      framebuffer: gl.createFramebuffer(),
      color: makeTexture(gl),
      depth: makeTexture(gl, true),
    };
    this.vao = gl.createVertexArray();
    this.captures = 0;
  }

  prepare(width, basis, angle, drawRabbit) {
    const gl = this.gl;
    const pixel = 180 / width;
    const w = 2 * Math.ceil(16 / pixel);
    const h = 2 * Math.ceil(24 / pixel);
    const factor = 1920 / width;
    const key = JSON.stringify([width, basis.forward, angle]);
    if (this.key === key) {
      return;
    }
    this.width = w;
    this.height = h;
    this.liftPixels = Math.round((16 * basis.up[1]) / pixel);
    const target = basis.up.map((v) => v * this.liftPixels * pixel);
    if (this.allocatedWidth !== width) {
      for (const [surface, scale] of [
        [this.high, factor],
        [this.low, 1],
      ]) {
        gl.activeTexture(gl.TEXTURE0);
        allocateTexture(gl, surface.color, w * scale, h * scale);
        allocateTexture(gl, surface.depth, w * scale, h * scale, true);
        gl.bindFramebuffer(gl.FRAMEBUFFER, surface.framebuffer);
        gl.framebufferTexture2D(
          gl.FRAMEBUFFER,
          gl.COLOR_ATTACHMENT0,
          gl.TEXTURE_2D,
          surface.color,
          0,
        );
        gl.framebufferTexture2D(
          gl.FRAMEBUFFER,
          gl.DEPTH_ATTACHMENT,
          gl.TEXTURE_2D,
          surface.depth,
          0,
        );
        if (gl.checkFramebufferStatus(gl.FRAMEBUFFER) !== gl.FRAMEBUFFER_COMPLETE) {
          throw new Error("Cannot allocate rabbit sprite color/depth capture.");
        }
      }
      this.allocatedWidth = width;
    }
    gl.bindFramebuffer(gl.FRAMEBUFFER, this.high.framebuffer);
    gl.viewport(0, 0, w * factor, h * factor);
    gl.enable(gl.DEPTH_TEST);
    gl.depthFunc(gl.LESS);
    gl.clearColor(0, 0, 0, 0);
    gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
    drawRabbit(target, [w * pixel, h * pixel]);
    gl.bindFramebuffer(gl.FRAMEBUFFER, this.low.framebuffer);
    gl.viewport(0, 0, w, h);
    gl.depthFunc(gl.ALWAYS);
    gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
    gl.useProgram(this.program);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, this.high.color);
    gl.activeTexture(gl.TEXTURE1);
    gl.bindTexture(gl.TEXTURE_2D, this.high.depth);
    gl.uniform1i(gl.getUniformLocation(this.program, "colorSource"), 0);
    gl.uniform1i(gl.getUniformLocation(this.program, "depthSource"), 1);
    gl.uniform1i(gl.getUniformLocation(this.program, "factor"), factor);
    gl.bindVertexArray(this.vao);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
    this.captures++;
    this.key = key;
  }

  capture() {
    const gl = this.gl;
    const pixels = new Uint8Array(this.width * this.height * 4);
    gl.bindFramebuffer(gl.FRAMEBUFFER, this.low.framebuffer);
    gl.readPixels(0, 0, this.width, this.height, gl.RGBA, gl.UNSIGNED_BYTE, pixels);
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    return pixels;
  }
}
