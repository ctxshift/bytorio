/* global document, window, requestAnimationFrame, fetch, performance */

import { RabbitSprite, makeTexture, allocateTexture } from "./river-sprite.js";
import { SurfaceCloud, WORLD_SAMPLE_SPACING } from "./river-surface.js";

const PRESENT_FRAGMENT = `#version 300 es
precision highp float;
precision highp int;
uniform sampler2D image;
uniform float scale;
uniform vec2 residual;
out vec4 result;
void main() {
  ivec2 at=ivec2(floor(gl_FragCoord.xy/scale+vec2(1.0)+residual));
  result=texelFetch(image,at,0);
}`;

const SCENE_VERTEX = `#version 300 es
precision highp float;
layout(location=0) in vec3 position;
layout(location=1) in vec4 color;
uniform vec3 translation;
uniform float rotation;
uniform vec3 target;
uniform vec3 right;
uniform vec3 up;
uniform vec3 forward;
uniform vec2 span;
out vec3 linearColor;
vec3 decode(vec3 c) {
  return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), greaterThan(c, vec3(0.04045)));
}
void main() {
  float s = sin(rotation), c = cos(rotation);
  vec3 p = vec3(position.x*c + position.z*s, position.y, -position.x*s + position.z*c);
  p += translation;
  vec2 projected=vec2(dot(p,right)-target.x,dot(p,up)-target.y);
  gl_Position = vec4(projected*2.0/span,
    (dot(p,forward)-target.z+260.0)/250.0-1.0, 1.0);
  linearColor = decode(color.rgb);
}`;

const SCENE_FRAGMENT = `#version 300 es
precision highp float;
in vec3 linearColor;
out vec4 result;
void main() { result = vec4(linearColor,1.0); }`;

const RESOLVE_VERTEX = `#version 300 es
precision highp float;
void main() {
  vec2 p = vec2(float((gl_VertexID << 1) & 2), float(gl_VertexID & 2));
  gl_Position = vec4(p*2.0-1.0,0.0,1.0);
}`;

const RESOLVE_FRAGMENT = `#version 300 es
precision highp float;
precision highp int;
uniform sampler2D source;
uniform int factor;
uniform bool useSprite;
uniform sampler2D spriteColor;
uniform sampler2D spriteDepth;
uniform sampler2D worldDepth;
uniform ivec2 spriteOffset;
uniform float spriteDepthOffset;
out vec4 result;
vec3 encode(vec3 c) {
  return mix(c * 12.92, 1.055 * pow(c, vec3(1.0/2.4)) - 0.055,
    greaterThan(c,vec3(0.0031308)));
}
void main() {
  ivec2 base = ivec2(gl_FragCoord.xy) * factor;
  vec3 sum = vec3(0.0);
  float nearestWorld=1.0;
  for (int y=0; y<6; y++) {
    for (int x=0; x<6; x++) {
      if (x<factor && y<factor) {
        sum += texelFetch(source,base+ivec2(x,y),0).rgb;
        if(useSprite) nearestWorld=min(nearestWorld,texelFetch(worldDepth,base+ivec2(x,y),0).r);
      }
    }
  }
  vec3 linearColor=sum/float(factor*factor);
  if(useSprite) {
    ivec2 at=ivec2(gl_FragCoord.xy)-spriteOffset;
    ivec2 size=textureSize(spriteColor,0);
    if(all(greaterThanEqual(at,ivec2(0))) && all(lessThan(at,size))) {
      vec4 c=texelFetch(spriteColor,at,0);
      float depth=texelFetch(spriteDepth,at,0).r+spriteDepthOffset;
      if(c.a>0.0 && depth<nearestWorld) linearColor=c.rgb+linearColor*(1.0-c.a);
    }
  }
  result = vec4(encode(linearColor),1.0);
}`;

function normalize(v) {
  const length = Math.hypot(...v);
  return v.map((value) => value / length);
}

function cross(a, b) {
  return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
}

function dot(a, b) {
  return a.reduce((sum, v, i) => sum + v * b[i], 0);
}

export function viewBasis(forward, yaw = 0) {
  const c = Math.cos(yaw);
  const s = Math.sin(yaw);
  const rotated = [forward[0] * c + forward[2] * s, forward[1], -forward[0] * s + forward[2] * c];
  const right = normalize(cross(rotated, [0, 1, 0]));
  return { forward: rotated, right, up: cross(right, rotated) };
}

export function snapToViewGrid(point, basis, pixel) {
  const dx = Math.round(dot(point, basis.right) / pixel) * pixel - dot(point, basis.right);
  const dy = Math.round(dot(point, basis.up) / pixel) * pixel - dot(point, basis.up);
  return point.map((v, i) => v + basis.right[i] * dx + basis.up[i] * dy);
}

export class RiverRenderer {
  constructor(canvas, metadata, world, rabbit) {
    const gl = canvas.getContext("webgl2", {
      antialias: false,
      alpha: false,
      preserveDrawingBuffer: true,
    });
    if (!gl) {
      throw new Error("This interactive comparison requires WebGL 2.");
    }
    this.gl = gl;
    // Observe explicit stores without GPU queries or readbacks in the live loop.
    const metrics = (this.metrics = { uploadBytes: 0, bufferBytes: 0, textureBytes: 0 });
    const buffers = new Map();
    const textures = new Map();
    const bindings = new Map();
    const textureBindings = new Map();
    let unit = gl.TEXTURE0;
    const bindBuffer = gl.bindBuffer.bind(gl);
    gl.bindBuffer = (target, buffer) => {
      bindings.set(target, buffer);
      return bindBuffer(target, buffer);
    };
    const bufferData = gl.bufferData.bind(gl);
    gl.bufferData = (target, data, usage) => {
      const bytes = typeof data === "number" ? data : data.byteLength;
      const buffer = bindings.get(target);
      metrics.bufferBytes += bytes - (buffers.get(buffer) || 0);
      buffers.set(buffer, bytes);
      if (typeof data !== "number") {
        metrics.uploadBytes += bytes;
      }
      return bufferData(target, data, usage);
    };
    const activeTexture = gl.activeTexture.bind(gl);
    gl.activeTexture = (value) => {
      unit = value;
      return activeTexture(value);
    };
    const bindTexture = gl.bindTexture.bind(gl);
    gl.bindTexture = (target, texture) => {
      textureBindings.set(unit, texture);
      return bindTexture(target, texture);
    };
    const texImage2D = gl.texImage2D.bind(gl);
    gl.texImage2D = (...args) => {
      const texture = textureBindings.get(unit);
      const bytes = args[3] * args[4] * 4;
      metrics.textureBytes += bytes - (textures.get(texture) || 0);
      textures.set(texture, bytes);
      if (args[8]?.byteLength) {
        metrics.uploadBytes += args[8].byteLength;
      }
      return texImage2D(...args);
    };
    this.canvas = canvas;
    this.metadata = metadata;
    const program = (vertex, fragment) => {
      const shaders = [
        [gl.VERTEX_SHADER, vertex],
        [gl.FRAGMENT_SHADER, fragment],
      ].map(([kind, source]) => {
        const shader = gl.createShader(kind);
        gl.shaderSource(shader, source);
        gl.compileShader(shader);
        if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
          throw new Error(gl.getShaderInfoLog(shader));
        }
        return shader;
      });
      const result = gl.createProgram();
      shaders.forEach((shader) => gl.attachShader(result, shader));
      gl.linkProgram(result);
      shaders.forEach((shader) => gl.deleteShader(shader));
      if (!gl.getProgramParameter(result, gl.LINK_STATUS)) {
        throw new Error(gl.getProgramInfoLog(result));
      }
      return result;
    };
    this.sceneProgram = program(SCENE_VERTEX, SCENE_FRAGMENT);
    this.resolveProgram = program(RESOLVE_VERTEX, RESOLVE_FRAGMENT);
    this.presentProgram = program(RESOLVE_VERTEX, PRESENT_FRAGMENT);
    this.presentUniforms = Object.fromEntries(
      ["image", "scale", "residual"].map((name) => [
        name,
        gl.getUniformLocation(this.presentProgram, name),
      ]),
    );
    this.presentationTexture = makeTexture(gl);
    this.presentationFramebuffer = gl.createFramebuffer();
    this.surface = new SurfaceCloud(gl, program, rabbit);
    this.makeWorldSurface = () => new SurfaceCloud(gl, program, world, WORLD_SAMPLE_SPACING);
    this.sprite = new RabbitSprite(gl, program);
    this.uniforms = Object.fromEntries(
      ["translation", "rotation", "target", "right", "up", "forward", "span"].map((name) => [
        name,
        gl.getUniformLocation(this.sceneProgram, name),
      ]),
    );
    this.factorUniform = gl.getUniformLocation(this.resolveProgram, "factor");
    this.spriteUniforms = Object.fromEntries(
      [
        "useSprite",
        "spriteColor",
        "spriteDepth",
        "worldDepth",
        "spriteOffset",
        "spriteDepthOffset",
      ].map((name) => [name, gl.getUniformLocation(this.resolveProgram, name)]),
    );
    gl.useProgram(this.resolveProgram);
    gl.uniform1i(gl.getUniformLocation(this.resolveProgram, "source"), 0);
    this.emptyVao = gl.createVertexArray();
    const upload = (bytes) => {
      const vao = gl.createVertexArray();
      gl.bindVertexArray(vao);
      const buffer = gl.createBuffer();
      gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
      gl.bufferData(gl.ARRAY_BUFFER, bytes, gl.STATIC_DRAW);
      gl.enableVertexAttribArray(0);
      gl.vertexAttribPointer(0, 3, gl.FLOAT, false, 16, 0);
      gl.enableVertexAttribArray(1);
      gl.vertexAttribPointer(1, 4, gl.UNSIGNED_BYTE, true, 16, 12);
      return vao;
    };
    this.world = upload(world);
    this.rabbit = upload(rabbit);
    this.framebuffer = gl.createFramebuffer();
    this.texture = gl.createTexture();
    this.depth = makeTexture(gl, true);
    gl.bindTexture(gl.TEXTURE_2D, this.texture);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.disable(gl.DITHER);
  }

  render(state) {
    const gl = this.gl;
    const width = state.width;
    const height = (width * 9) / 16;
    const smooth = Boolean(state.smoothPresentation && state.stabilization !== "continuous");
    const border = smooth ? 1 : 0;
    const renderWidth = width + border * 2;
    const renderHeight = height + border * 2;
    const factor = state.supersampling ? 1920 / width : 1;
    const internalWidth = renderWidth * factor;
    const internalHeight = renderHeight * factor;
    const scale = smooth
      ? Math.max(1, Math.min(6, Math.floor(state.presentationWidth / width) || 1))
      : 1;
    if (this.canvas.width !== width * scale || this.canvas.height !== height * scale) {
      this.canvas.width = width * scale;
      this.canvas.height = height * scale;
    }
    if (this.internalWidth !== internalWidth) {
      gl.bindTexture(gl.TEXTURE_2D, this.texture);
      gl.texImage2D(
        gl.TEXTURE_2D,
        0,
        gl.RGBA8,
        internalWidth,
        internalHeight,
        0,
        gl.RGBA,
        gl.UNSIGNED_BYTE,
        null,
      );
      allocateTexture(gl, this.depth, internalWidth, internalHeight, true);
      gl.bindFramebuffer(gl.FRAMEBUFFER, this.framebuffer);
      gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, this.texture, 0);
      gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.TEXTURE_2D, this.depth, 0);
      if (gl.checkFramebufferStatus(gl.FRAMEBUFFER) !== gl.FRAMEBUFFER_COMPLETE) {
        throw new Error("Cannot allocate the scene color/depth target.");
      }
      this.internalWidth = internalWidth;
      this.internalHeight = internalHeight;
    }
    gl.bindFramebuffer(gl.FRAMEBUFFER, this.framebuffer);
    gl.viewport(0, 0, internalWidth, internalHeight);
    gl.enable(gl.DEPTH_TEST);
    gl.depthFunc(gl.LESS);
    gl.clearColor(0, 0, 0, 1);
    gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
    gl.useProgram(this.sceneProgram);
    const basis = viewBasis(this.metadata.camera.forward, state.yaw || 0);
    const { forward, right, up } = basis;
    const pixel = this.metadata.camera.viewWidth / width;
    const snapped = state.stabilization !== "continuous";
    const target = snapped ? snapToViewGrid(state.target, basis, pixel) : state.target;
    const rabbit = snapped ? snapToViewGrid(state.rabbit, basis, pixel) : state.rabbit;
    this.renderPose = { target: [...target], rabbit: [...rabbit] };
    const u = this.uniforms;
    gl.uniform3fv(u.forward, forward);
    gl.uniform3fv(u.right, right);
    gl.uniform3fv(u.up, up);
    // Subtract snapped view coordinates after projection so integer camera steps
    // do not perturb world-space dot-product rounding at supersample boundaries.
    gl.uniform3fv(u.target, [dot(target, right), dot(target, up), dot(target, forward)]);
    const span = [renderWidth * pixel, renderHeight * pixel];
    gl.uniform2fv(u.span, span);
    gl.uniform3f(u.translation, 0, 0, 0);
    gl.uniform1f(u.rotation, 0);
    if (state.stabilization === "scene-surface") {
      if (!this.worldSurface) {
        this.worldSurface = this.makeWorldSurface();
        this.makeWorldSurface = null;
      }
      this.worldSurface.draw(basis, target, [0, 0, 0], 0, span, pixel, factor);
    } else {
      gl.bindVertexArray(this.world);
      gl.drawArrays(gl.TRIANGLES, 0, this.metadata.worldVertices);
    }
    if (state.stabilization === "surface" || state.stabilization === "scene-surface") {
      this.surface.draw(basis, target, rabbit, state.angle, span, pixel, factor);
    } else if (state.stabilization !== "sprite") {
      gl.uniform3fv(u.translation, rabbit);
      gl.uniform1f(u.rotation, state.angle);
      gl.bindVertexArray(this.rabbit);
      gl.drawArrays(gl.TRIANGLES, 0, this.metadata.rabbitVertices);
    } else {
      this.sprite.prepare(width, basis, state.angle, (localTarget, span) => {
        gl.useProgram(this.sceneProgram);
        gl.uniform3fv(u.target, [
          dot(localTarget, right),
          dot(localTarget, up),
          dot(localTarget, forward),
        ]);
        gl.uniform2fv(u.span, span);
        gl.uniform3f(u.translation, 0, 0, 0);
        gl.uniform1f(u.rotation, state.angle);
        gl.bindVertexArray(this.rabbit);
        gl.drawArrays(gl.TRIANGLES, 0, this.metadata.rabbitVertices);
      });
    }
    this.presentation = null;
    if (smooth) {
      const offset = state.target.map((v, i) => v - target[i]);
      this.presentation = {
        scale,
        residual: [right, up].map(
          (axis) => Math.round((dot(offset, axis) / pixel) * scale) / scale,
        ),
        logicalWidth: width,
        logicalHeight: height,
      };
      if (this.presentationWidth !== renderWidth) {
        allocateTexture(gl, this.presentationTexture, renderWidth, renderHeight, false);
        gl.bindFramebuffer(gl.FRAMEBUFFER, this.presentationFramebuffer);
        gl.framebufferTexture2D(
          gl.FRAMEBUFFER,
          gl.COLOR_ATTACHMENT0,
          gl.TEXTURE_2D,
          this.presentationTexture,
          0,
        );
        if (gl.checkFramebufferStatus(gl.FRAMEBUFFER) !== gl.FRAMEBUFFER_COMPLETE) {
          throw new Error("Cannot allocate the overscan presentation target.");
        }
        this.presentationWidth = renderWidth;
      }
    }
    this.resolve(
      renderWidth,
      renderHeight,
      factor,
      state.stabilization === "sprite"
        ? {
            offset: [
              Math.round(
                dot(
                  rabbit.map((v, i) => v - target[i]),
                  right,
                ) / pixel,
              ) +
                renderWidth / 2 -
                this.sprite.width / 2,
              Math.round(
                dot(
                  rabbit.map((v, i) => v - target[i]),
                  up,
                ) / pixel,
              ) +
                renderHeight / 2 +
                this.sprite.liftPixels -
                this.sprite.height / 2,
            ],
            depthOffset:
              dot(
                rabbit.map((v, i) => v - target[i]),
                forward,
              ) / 500,
          }
        : null,
    );
  }

  resolve(width, height, factor, sprite = null) {
    const gl = this.gl;
    gl.bindFramebuffer(gl.FRAMEBUFFER, this.presentation ? this.presentationFramebuffer : null);
    gl.viewport(0, 0, width, height);
    gl.disable(gl.DEPTH_TEST);
    gl.useProgram(this.resolveProgram);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, this.texture);
    gl.uniform1i(this.factorUniform, factor);
    const u = this.spriteUniforms;
    gl.uniform1i(u.useSprite, Number(sprite !== null));
    if (sprite) {
      for (const [unit, texture] of [
        [1, this.sprite.low.color],
        [2, this.sprite.low.depth],
        [3, this.depth],
      ]) {
        gl.activeTexture(gl.TEXTURE0 + unit);
        gl.bindTexture(gl.TEXTURE_2D, texture);
      }
      gl.uniform1i(u.spriteColor, 1);
      gl.uniform1i(u.spriteDepth, 2);
      gl.uniform1i(u.worldDepth, 3);
      gl.uniform2iv(u.spriteOffset, sprite.offset);
      gl.uniform1f(u.spriteDepthOffset, sprite.depthOffset);
    }
    gl.bindVertexArray(this.emptyVao);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
    if (this.presentation) {
      const p = this.presentation;
      gl.bindFramebuffer(gl.FRAMEBUFFER, null);
      gl.viewport(0, 0, this.canvas.width, this.canvas.height);
      gl.useProgram(this.presentProgram);
      gl.activeTexture(gl.TEXTURE0);
      gl.bindTexture(gl.TEXTURE_2D, this.presentationTexture);
      gl.uniform1i(this.presentUniforms.image, 0);
      gl.uniform1f(this.presentUniforms.scale, p.scale);
      gl.uniform2fv(this.presentUniforms.residual, p.residual);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
    }
  }

  capture() {
    const gl = this.gl;
    const source = new Uint8Array(this.internalWidth * this.internalHeight * 4);
    const output = new Uint8Array(this.canvas.width * this.canvas.height * 4);
    gl.bindFramebuffer(gl.FRAMEBUFFER, this.framebuffer);
    gl.readPixels(0, 0, this.internalWidth, this.internalHeight, gl.RGBA, gl.UNSIGNED_BYTE, source);
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    gl.readPixels(0, 0, this.canvas.width, this.canvas.height, gl.RGBA, gl.UNSIGNED_BYTE, output);
    return { source, output };
  }
}

async function start() {
  const canvas = document.querySelector("#scene");
  const state = (window.riverDemo = {
    ready: false,
    error: "",
    width: 640,
    supersampling: false,
    frame: 0,
    angle: 0,
    yaw: 0,
    stabilization: "continuous",
  });
  try {
    const load = async (name, type) => {
      const response = await fetch(name);
      if (!response.ok) {
        throw new Error(`Cannot load ${name}: ${response.status}`);
      }
      return response[type]();
    };
    const [metadata, world, rabbit] = await Promise.all([
      load("live-scene.json", "json"),
      load("world.bin", "arrayBuffer"),
      load("rabbit.bin", "arrayBuffer"),
    ]);
    const renderer = new RiverRenderer(canvas, metadata, world, rabbit);
    const stats = document.createElement("output");
    stats.id = "performance";
    stats.style.cssText =
      "position:absolute;top:8px;left:8px;white-space:pre-line;font:12px/1.5 monospace;padding:8px;background:#000b;color:white;pointer-events:none";
    canvas.parentElement.style.position = "relative";
    canvas.parentElement.append(stats);
    let statsTime = performance.now(),
      statsFrames = 0,
      statsUploads = renderer.metrics.uploadBytes;
    state.renderer = renderer;
    state.rabbit = [...metadata.rabbitOrigin];
    state.target = [...metadata.camera.target];
    const keys = new Set();
    const pan = [0, 0];
    let clock = 0;
    let previous = performance.now();
    const native = document.querySelector("#native");
    const actual = document.querySelector("#actual");
    const ssaa = document.querySelector("#supersampling");
    const stabilization = document.querySelector("#stabilization");
    const smooth = document.querySelector("#smooth-presentation");
    const walkHeight = (x, z) => {
      const w = metadata.walk;
      x = Math.round(x);
      z = Math.round(z);
      if (x < w.minX || x > w.maxX || z < w.minZ || z > w.maxZ) {
        return -1;
      }
      return w.heights[(z - w.minZ) * (w.maxX - w.minX + 1) + x - w.minX];
    };
    const move = (x, z) => {
      const height = walkHeight(x, z);
      if (height < 0 || Math.abs(height - state.rabbit[1]) > 2) {
        return;
      }
      for (const [dx, dz] of [
        [-1, -1],
        [-1, 1],
        [1, -1],
        [1, 1],
      ]) {
        const edge = walkHeight(x + dx, z + dz);
        if (edge < 0 || Math.abs(edge - height) > 2) {
          return;
        }
      }
      state.rabbit = [x, height, z];
    };
    const updatePresentation = () => {
      document.querySelector("#frame").classList.toggle("native", native.checked);
      document
        .querySelector("#frame")
        .classList.toggle("actual", actual.checked && !native.checked);
      ssaa.disabled = state.width === 1920;
      state.supersampling = ssaa.checked && !ssaa.disabled;
      state.stabilization = stabilization.value;
      smooth.disabled = native.checked || state.stabilization === "continuous";
      state.smoothPresentation = smooth.checked && !smooth.disabled;
    };
    for (const button of document.querySelectorAll("button[data-width]")) {
      button.addEventListener("click", () => {
        state.width = Number(button.dataset.width);
        for (const other of document.querySelectorAll("button[data-width]")) {
          other.setAttribute("aria-pressed", String(other === button));
        }
        updatePresentation();
      });
    }
    native.addEventListener("change", () => {
      if (native.checked) {
        actual.checked = false;
      }
      updatePresentation();
    });
    actual.addEventListener("change", () => {
      if (actual.checked) {
        native.checked = false;
      }
      updatePresentation();
    });
    ssaa.addEventListener("change", updatePresentation);
    stabilization.addEventListener("change", updatePresentation);
    smooth.addEventListener("change", updatePresentation);
    document.querySelector("#reset").addEventListener("click", () => {
      state.rabbit = [...metadata.rabbitOrigin];
      state.angle = 0;
      state.yaw = 0;
      pan.fill(0);
      clock = 0;
      keys.clear();
    });
    canvas.addEventListener("pointerdown", () => canvas.focus());
    window.addEventListener("keydown", (event) => {
      if (
        !canvas.matches(":focus") ||
        ![
          "KeyW",
          "KeyA",
          "KeyS",
          "KeyD",
          "KeyQ",
          "KeyE",
          "ArrowLeft",
          "ArrowRight",
          "ArrowUp",
          "ArrowDown",
        ].includes(event.code)
      ) {
        return;
      }
      event.preventDefault();
      keys.add(event.code);
    });
    window.addEventListener("keyup", (event) => keys.delete(event.code));
    window.addEventListener("blur", () => keys.clear());
    canvas.addEventListener("blur", () => keys.clear());
    canvas.addEventListener("webglcontextlost", (event) => {
      event.preventDefault();
      state.error = "Graphics context lost. Reload the page to continue.";
    });
    const tick = (now) => {
      try {
        if (state.error) {
          throw new Error(state.error);
        }
        const dt = Math.min((now - previous) / 1000, 0.05);
        previous = now;
        if (!document.querySelector("#pause").checked && !document.hidden) {
          clock += dt;
          const turning = Number(keys.has("KeyE")) - Number(keys.has("KeyQ"));
          state.yaw +=
            dt * (turning * 0.7 + (document.querySelector("#camera-orbit").checked ? 0.18 : 0));
          state.yaw = Math.atan2(Math.sin(state.yaw), Math.cos(state.yaw));
          let dx = Number(keys.has("KeyD")) - Number(keys.has("KeyA"));
          let dz = Number(keys.has("KeyS")) - Number(keys.has("KeyW"));
          const length = Math.hypot(dx, dz);
          if (length) {
            dx /= length;
            dz /= length;
            const basis = viewBasis(metadata.camera.forward, state.yaw);
            const forwardGround = normalize([basis.forward[0], 0, basis.forward[2]]);
            [dx, dz] = [
              basis.right[0] * dx - forwardGround[0] * dz,
              basis.right[2] * dx - forwardGround[2] * dz,
            ];
            move(state.rabbit[0] + dx * dt * 12, state.rabbit[2]);
            move(state.rabbit[0], state.rabbit[2] + dz * dt * 12);
            state.angle = Math.atan2(dx, dz);
          }
          pan[0] = Math.max(
            -12,
            Math.min(
              12,
              pan[0] + (Number(keys.has("ArrowRight")) - Number(keys.has("ArrowLeft"))) * dt * 7,
            ),
          );
          pan[1] = Math.max(
            -12,
            Math.min(
              12,
              pan[1] + (Number(keys.has("ArrowDown")) - Number(keys.has("ArrowUp"))) * dt * 7,
            ),
          );
        }
        const follow = document.querySelector("#follow").checked ? 0.3 : 0;
        const auto = document.querySelector("#camera-motion").checked;
        state.target = [
          metadata.camera.target[0] +
            pan[0] +
            (state.rabbit[0] + 4) * follow +
            (auto ? Math.sin(clock * 0.45) * 3 : 0),
          metadata.camera.target[1],
          metadata.camera.target[2] +
            pan[1] +
            (state.rabbit[2] - 19) * follow +
            (auto ? Math.sin(clock * 0.33) * 3 : 0),
        ];
        state.presentationWidth = canvas.clientWidth * window.devicePixelRatio;
        renderer.render(state);
        statsFrames++;
        if (now - statsTime >= 500) {
          const elapsed = now - statsTime;
          const m = renderer.metrics;
          const mib = (bytes) => (bytes / 1048576).toFixed(2);
          state.metrics = {
            fps: (statsFrames * 1000) / elapsed,
            gpuUploadBytesPerSecond: ((m.uploadBytes - statsUploads) * 1000) / elapsed,
            ...m,
          };
          stats.textContent = `${state.metrics.fps.toFixed(1)} FPS rendered\nGPU uploads ${mib(state.metrics.gpuUploadBytesPerSecond)} MiB/s · total ${mib(m.uploadBytes)} MiB\nGPU buffers ${mib(m.bufferBytes)} MiB · textures ${mib(m.textureBytes)} MiB (est.)\nSource geometry ${mib(world.byteLength + rabbit.byteLength)} MiB CPU data (excludes JS heap and driver)`;
          statsTime = now;
          statsFrames = 0;
          statsUploads = m.uploadBytes;
        }
        state.frame++;
        state.internalWidth = renderer.internalWidth;
        state.internalHeight = renderer.internalHeight;
        state.renderPose = renderer.renderPose;
        state.spriteCaptures = renderer.sprite.captures;
        const bounds = canvas.getBoundingClientRect();
        document.querySelector("#dimensions").textContent =
          `${stabilization.selectedOptions[0].textContent} · ${state.supersampling ? "Filtered 1080p" : "Direct"}: ${renderer.internalWidth} × ${renderer.internalHeight} → ${state.width} × ${(state.width * 9) / 16} game pixels · Canvas: ${canvas.width} × ${canvas.height}${renderer.presentation ? ` · Smooth pan ${renderer.presentation.scale}× (1-pixel overscan)` : ""} · Displayed: ${Math.round(bounds.width)} × ${Math.round(bounds.height)} CSS pixels${state.stabilization === "surface" || state.stabilization === "scene-surface" ? ` · ${renderer.surface.count} fixed rabbit samples` : ""}${state.stabilization === "scene-surface" ? ` + ${renderer.worldSurface.count} world samples (0.5-unit spacing, ${(renderer.worldSurface.samples.byteLength / 1048576).toFixed(1)} MiB each CPU/GPU)` : ""}`;
        requestAnimationFrame(tick);
      } catch (error) {
        state.error = error.message;
        document.querySelector("#dimensions").textContent = state.error;
      }
    };
    updatePresentation();
    renderer.render(state);
    state.ready = true;
    requestAnimationFrame(tick);
  } catch (error) {
    state.error = error.message;
    document.querySelector("#dimensions").textContent = state.error;
  }
}

if (document.querySelector("#scene")) {
  start();
}
