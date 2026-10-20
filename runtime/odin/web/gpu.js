const RASTER_VERTEX_BYTES = 7 * Float32Array.BYTES_PER_ELEMENT;

export function normalizeGraphics(value = {}) {
  const backend = value.backend || "cpu";
  const ssaa = value.ssaa || "off";
  if (!["cpu", "gpu", "auto"].includes(backend) || !["off", "2x", "1080p"].includes(ssaa)) {
    throw new Error("Invalid graphics settings.");
  }
  if (backend === "cpu" && (ssaa !== "off" || value.pixelSnap || value.smoothPan)) {
    throw new Error("Supersampling and camera presentation settings require the GPU renderer.");
  }
  return {
    backend,
    ssaa,
    pixelSnap: Boolean(value.pixelSnap || value.smoothPan),
    smoothPan: Boolean(value.smoothPan),
  };
}

export async function createGpu(settings) {
  const canvas = new OffscreenCanvas(1, 1);
  const gl = canvas.getContext("webgl2", { antialias: false, alpha: false });
  if (!gl) {
    throw new Error("WebGL 2 is unavailable.");
  }
  const names = ["fullscreen.vert", "mesh.vert", "initialize.frag", "mesh.frag", "resolve.frag"];
  const sources = Object.fromEntries(
    await Promise.all(
      names.map(async (name) => {
        const response = await fetch(`./gpu-shaders/${name}`);
        if (!response.ok) {
          throw new Error(`Cannot load GPU shader ${name}.`);
        }
        return [name, await response.text()];
      }),
    ),
  );
  const compile = (kind, code) => {
    const shader = gl.createShader(kind);
    gl.shaderSource(
      shader,
      `#version 300 es\nprecision highp float;\nprecision highp int;\n${code}`,
    );
    gl.compileShader(shader);
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
      throw new Error(gl.getShaderInfoLog(shader));
    }
    return shader;
  };
  const program = (vertex, fragment) => {
    const shaders = [
      compile(gl.VERTEX_SHADER, sources[vertex]),
      compile(gl.FRAGMENT_SHADER, sources[fragment]),
    ];
    const p = gl.createProgram();
    shaders.forEach((s) => gl.attachShader(p, s));
    gl.linkProgram(p);
    shaders.forEach((s) => gl.deleteShader(s));
    if (!gl.getProgramParameter(p, gl.LINK_STATUS)) {
      throw new Error(gl.getProgramInfoLog(p));
    }
    return p;
  };
  const init = program("fullscreen.vert", "initialize.frag");
  const mesh = program("mesh.vert", "mesh.frag");
  const resolve = program("fullscreen.vert", "resolve.frag");
  const texture = () => {
    const t = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, t);
    for (const parameter of [gl.TEXTURE_MIN_FILTER, gl.TEXTURE_MAG_FILTER]) {
      gl.texParameteri(gl.TEXTURE_2D, parameter, gl.NEAREST);
    }
    for (const parameter of [gl.TEXTURE_WRAP_S, gl.TEXTURE_WRAP_T]) {
      gl.texParameteri(gl.TEXTURE_2D, parameter, gl.CLAMP_TO_EDGE);
    }
    return t;
  };
  const input = [texture(), texture()];
  const high = {
    fbo: gl.createFramebuffer(),
    color: texture(),
    depthBits: texture(),
    depth: texture(),
  };
  const low = { fbo: gl.createFramebuffer(), color: texture(), depthBits: texture() };
  const vao = gl.createVertexArray();
  gl.bindVertexArray(vao);
  const buffer = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
  gl.enableVertexAttribArray(0);
  gl.vertexAttribPointer(0, 4, gl.FLOAT, false, RASTER_VERTEX_BYTES, 0);
  gl.enableVertexAttribArray(1);
  gl.vertexAttribPointer(1, 3, gl.FLOAT, false, RASTER_VERTEX_BYTES, 16);
  gl.disable(gl.DITHER);
  const allocate = (t, w, h, depth = false, bytes = null) => {
    gl.bindTexture(gl.TEXTURE_2D, t);
    gl.texImage2D(
      gl.TEXTURE_2D,
      0,
      depth ? gl.DEPTH_COMPONENT32F : gl.RGBA8,
      w,
      h,
      0,
      depth ? gl.DEPTH_COMPONENT : gl.RGBA,
      depth ? gl.FLOAT : gl.UNSIGNED_BYTE,
      bytes,
    );
  };
  const target = (value, w, h) => {
    gl.bindFramebuffer(gl.FRAMEBUFFER, value.fbo);
    for (const [t, attachment, depth] of [
      [value.color, gl.COLOR_ATTACHMENT0, false],
      [value.depthBits, gl.COLOR_ATTACHMENT1, false],
      ...(value.depth ? [[value.depth, gl.DEPTH_ATTACHMENT, true]] : []),
    ]) {
      allocate(t, w, h, depth);
      gl.framebufferTexture2D(gl.FRAMEBUFFER, attachment, gl.TEXTURE_2D, t, 0);
    }
    gl.drawBuffers([gl.COLOR_ATTACHMENT0, gl.COLOR_ATTACHMENT1]);
    if (gl.checkFramebufferStatus(gl.FRAMEBUFFER) !== gl.FRAMEBUFFER_COMPLETE) {
      throw new Error("GPU framebuffer is incomplete.");
    }
  };
  let dimensions = "",
    resultColor,
    resultDepth;
  const quad = (p, a, b, factor, w, h, border = 0) => {
    gl.useProgram(p);
    for (const [unit, t, name] of [
      [0, a, "colorSource"],
      [1, b, "depthSource"],
    ]) {
      gl.activeTexture(gl.TEXTURE0 + unit);
      gl.bindTexture(gl.TEXTURE_2D, t);
      gl.uniform1i(gl.getUniformLocation(p, name), unit);
    }
    gl.uniform1i(gl.getUniformLocation(p, "factor"), factor);
    gl.uniform1i(gl.getUniformLocation(p, "border"), border);
    gl.viewport(0, 0, w, h);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
  };
  return {
    gl,
    raster(
      memory,
      vertices,
      count,
      color,
      depth,
      width,
      height,
      cx,
      cy,
      cw,
      ch,
      fogColor,
      fogStart,
      fogEnd,
      borderOutput = 0,
    ) {
      if (width < 1 || height < 1 || width > 1920 || height > 1080) {
        return 0;
      }
      const desiredFactor =
        settings.ssaa === "1080p"
          ? Math.max(1, Math.min(6, Math.floor(1920 / width), Math.floor(1080 / height)))
          : settings.ssaa === "2x"
            ? 2
            : 1;
      const factor = Math.max(
        1,
        Math.min(desiredFactor, Math.floor(1920 / width), Math.floor(1080 / height)),
      );
      const border = borderOutput ? 1 : 0;
      const rw = width + border * 2,
        rh = height + border * 2;
      if (rw * rh * factor * factor > 1932 * 1092) {
        return 0;
      }
      const key = `${rw}/${rh}/${factor}`;
      if (dimensions !== key) {
        target(high, rw * factor, rh * factor);
        target(low, rw, rh);
        resultColor = new Uint8Array(rw * rh * 4);
        resultDepth = new Uint8Array(rw * rh * 4);
        dimensions = key;
      }
      gl.bindVertexArray(vao);
      gl.disable(gl.SCISSOR_TEST);
      gl.bindFramebuffer(gl.FRAMEBUFFER, high.fbo);
      gl.enable(gl.DEPTH_TEST);
      gl.depthFunc(gl.ALWAYS);
      gl.activeTexture(gl.TEXTURE0);
      allocate(
        input[0],
        width,
        height,
        false,
        new Uint8Array(memory.buffer, color, width * height * 4),
      );
      allocate(
        input[1],
        width,
        height,
        false,
        new Uint8Array(memory.buffer, depth, width * height * 4),
      );
      quad(init, input[0], input[1], factor, rw * factor, rh * factor, border);
      gl.depthFunc(gl.LESS);
      gl.enable(gl.SCISSOR_TEST);
      const x0 = Math.max(0, cx),
        y0 = Math.max(0, cy),
        x1 = Math.min(width, cx + cw),
        y1 = Math.min(height, cy + ch);
      gl.scissor(
        x0 * factor,
        y0 * factor,
        Math.max(0, x1 - x0) * factor,
        Math.max(0, y1 - y0) * factor,
      );
      if (border) {
        gl.disable(gl.SCISSOR_TEST);
      }
      gl.useProgram(mesh);
      gl.uniform2f(gl.getUniformLocation(mesh, "logicalSize"), width, height);
      gl.uniform1i(gl.getUniformLocation(mesh, "border"), border);
      gl.uniform3f(
        gl.getUniformLocation(mesh, "fogColor"),
        (fogColor & 255) / 255,
        ((fogColor >>> 8) & 255) / 255,
        ((fogColor >>> 16) & 255) / 255,
      );
      gl.uniform2f(gl.getUniformLocation(mesh, "fogRange"), fogStart, fogEnd);
      gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
      gl.bufferData(
        gl.ARRAY_BUFFER,
        new Uint8Array(memory.buffer, vertices, count * RASTER_VERTEX_BYTES),
        gl.STREAM_DRAW,
      );
      gl.drawArrays(gl.TRIANGLES, 0, count);
      gl.disable(gl.SCISSOR_TEST);
      gl.disable(gl.DEPTH_TEST);
      gl.bindFramebuffer(gl.FRAMEBUFFER, low.fbo);
      quad(resolve, high.color, high.depthBits, factor, rw, rh);
      gl.readBuffer(gl.COLOR_ATTACHMENT0);
      gl.readPixels(0, 0, rw, rh, gl.RGBA, gl.UNSIGNED_BYTE, resultColor);
      gl.readBuffer(gl.COLOR_ATTACHMENT1);
      gl.readPixels(0, 0, rw, rh, gl.RGBA, gl.UNSIGNED_BYTE, resultDepth);
      if (gl.getError() !== gl.NO_ERROR || gl.isContextLost()) {
        return 0;
      }
      for (let y = 0; y < height; y++) {
        const source = ((y + border) * rw + border) * 4;
        new Uint8Array(memory.buffer, color + y * width * 4, width * 4).set(
          resultColor.subarray(source, source + width * 4),
        );
        new Uint8Array(memory.buffer, depth + y * width * 4, width * 4).set(
          resultDepth.subarray(source, source + width * 4),
        );
      }
      if (borderOutput) {
        new Uint8Array(memory.buffer, borderOutput, resultColor.length).set(resultColor);
      }
      return 1;
    },
  };
}
