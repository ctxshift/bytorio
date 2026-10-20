/* global document, window, requestAnimationFrame, fetch, performance */

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
  p += translation - target;
  gl_Position = vec4(dot(p,right)*2.0/span.x, dot(p,up)*2.0/span.y,
    (dot(p,forward)+260.0)/250.0-1.0, 1.0);
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
out vec4 result;
vec3 encode(vec3 c) {
  return mix(c * 12.92, 1.055 * pow(c, vec3(1.0/2.4)) - 0.055,
    greaterThan(c,vec3(0.0031308)));
}
void main() {
  ivec2 base = ivec2(gl_FragCoord.xy) * factor;
  vec3 sum = vec3(0.0);
  for (int y=0; y<6; y++) {
    for (int x=0; x<6; x++) {
      if (x<factor && y<factor) { sum += texelFetch(source,base+ivec2(x,y),0).rgb; }
    }
  }
  result = vec4(encode(sum/float(factor*factor)),1.0);
}`;

function normalize(v) {
  const length = Math.hypot(...v);
  return v.map((value) => value / length);
}

function cross(a, b) {
  return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
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
    this.uniforms = Object.fromEntries(
      ["translation", "rotation", "target", "right", "up", "forward", "span"].map((name) => [
        name,
        gl.getUniformLocation(this.sceneProgram, name),
      ]),
    );
    this.factorUniform = gl.getUniformLocation(this.resolveProgram, "factor");
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
    this.depth = gl.createRenderbuffer();
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
    const internalWidth = state.supersampling ? 1920 : width;
    const internalHeight = (internalWidth * 9) / 16;
    if (this.canvas.width !== width || this.canvas.height !== height) {
      this.canvas.width = width;
      this.canvas.height = height;
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
      gl.bindRenderbuffer(gl.RENDERBUFFER, this.depth);
      gl.renderbufferStorage(gl.RENDERBUFFER, gl.DEPTH_COMPONENT24, internalWidth, internalHeight);
      gl.bindFramebuffer(gl.FRAMEBUFFER, this.framebuffer);
      gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, this.texture, 0);
      gl.framebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.RENDERBUFFER, this.depth);
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
    const forward = this.metadata.camera.forward;
    const right = normalize(cross(forward, [0, 1, 0]));
    const up = cross(right, forward);
    const u = this.uniforms;
    gl.uniform3fv(u.forward, forward);
    gl.uniform3fv(u.right, right);
    gl.uniform3fv(u.up, up);
    gl.uniform3fv(u.target, state.target);
    gl.uniform2f(u.span, this.metadata.camera.viewWidth, (this.metadata.camera.viewWidth * 9) / 16);
    gl.uniform3f(u.translation, 0, 0, 0);
    gl.uniform1f(u.rotation, 0);
    gl.bindVertexArray(this.world);
    gl.drawArrays(gl.TRIANGLES, 0, this.metadata.worldVertices);
    gl.uniform3fv(u.translation, state.rabbit);
    gl.uniform1f(u.rotation, state.angle);
    gl.bindVertexArray(this.rabbit);
    gl.drawArrays(gl.TRIANGLES, 0, this.metadata.rabbitVertices);
    this.resolve(width, height, internalWidth / width);
  }

  resolve(width, height, factor) {
    const gl = this.gl;
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    gl.viewport(0, 0, width, height);
    gl.disable(gl.DEPTH_TEST);
    gl.useProgram(this.resolveProgram);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, this.texture);
    gl.uniform1i(this.factorUniform, factor);
    gl.bindVertexArray(this.emptyVao);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
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
    document.querySelector("#reset").addEventListener("click", () => {
      state.rabbit = [...metadata.rabbitOrigin];
      state.angle = 0;
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
          let dx = Number(keys.has("KeyD")) - Number(keys.has("KeyA"));
          let dz = Number(keys.has("KeyS")) - Number(keys.has("KeyW"));
          const length = Math.hypot(dx, dz);
          if (length) {
            dx /= length;
            dz /= length;
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
        renderer.render(state);
        state.frame++;
        state.internalWidth = renderer.internalWidth;
        state.internalHeight = renderer.internalHeight;
        const bounds = canvas.getBoundingClientRect();
        document.querySelector("#dimensions").textContent =
          `${state.supersampling ? "Filtered 1080p" : "Direct"}: ${renderer.internalWidth} × ${renderer.internalHeight} → ${canvas.width} × ${canvas.height} pixels · Displayed: ${Math.round(bounds.width)} × ${Math.round(bounds.height)} CSS pixels`;
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
