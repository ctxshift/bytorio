import { surfacePatches, SURFACE_POINTS_PER_PATCH } from "./gpu-surface.js";

const RASTER_VERTEX_BYTES = 7 * Float32Array.BYTES_PER_ELEMENT;
const RESIDENT_VERTEX_FLOATS = 12;
const GPU_CACHE_BYTES = 64 * 1024 * 1024;
const GPU_CACHE_ENTRIES = 1024;

export function normalizeGraphics(value = {}) {
  const backend = value.backend || "cpu";
  const ssaa = value.ssaa || "off";
  if (!["cpu", "gpu", "auto"].includes(backend) || !["off", "2x", "1080p"].includes(ssaa)) {
    throw new Error("Invalid graphics settings.");
  }
  if (backend === "cpu" && value.surfaceSamples) {
    throw new Error("Whole-scene surface samples require the GPU renderer.");
  }
  if (backend === "cpu" && value.residentMeshes) {
    throw new Error("Resident meshes require the GPU renderer.");
  }
  return {
    backend,
    ssaa,
    pixelSnap: Boolean(value.pixelSnap || value.smoothPan || value.surfaceSamples),
    smoothPan: Boolean(value.smoothPan),
    residentMeshes: Boolean(value.residentMeshes || value.surfaceSamples),
    surfaceSamples: Boolean(value.surfaceSamples),
  };
}

export async function createGpu(settings) {
  const canvas = new OffscreenCanvas(1, 1);
  const gl = canvas.getContext("webgl2", { antialias: false, alpha: false });
  if (!gl) {
    throw new Error("WebGL 2 is unavailable.");
  }
  const names = [
    "fullscreen.vert",
    "mesh.vert",
    "initialize.frag",
    "mesh.frag",
    "resolve.frag",
    "resident.vert",
    "present.frag",
  ];
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
  const resident = program("resident.vert", "mesh.frag");
  const presentProgram = program("fullscreen.vert", "present.frag");
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
  const presentInput = [texture(), texture()];
  const hud = texture();
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
  const residentVao = gl.createVertexArray();
  gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
  gl.enableVertexAttribArray(0);
  gl.vertexAttribPointer(0, 4, gl.FLOAT, false, RASTER_VERTEX_BYTES, 0);
  gl.enableVertexAttribArray(1);
  gl.vertexAttribPointer(1, 3, gl.FLOAT, false, RASTER_VERTEX_BYTES, 16);
  gl.disable(gl.DITHER);
  const cache = new Map();
  let cacheBytes = 0;
  const metrics = {
    meshUploads: 0,
    cacheHits: 0,
    uploadBytes: 0,
    textureUploadBytes: 0,
    cacheBytes: 0,
    textureBytes: 0,
  };
  const textureStorage = new Map();
  let draws = [];
  const clearMeshes = () => {
    for (const entry of cache.values()) {
      gl.deleteBuffer(entry.buffer);
    }
    cache.clear();
    cacheBytes = 0;
    metrics.cacheBytes = 0;
  };
  const cachedMesh = (memory, draw) => {
    const key = `${draw.high}:${draw.low}`;
    const palette = draw.palette ? new Uint8Array(memory.buffer, draw.palette, 1024) : null;
    let entry = cache.get(key);
    const same =
      entry &&
      Boolean(palette) === Boolean(entry.palette) &&
      (!palette || palette.every((value, i) => value === entry.palette[i]));
    if (same) {
      metrics.cacheHits++;
      return entry;
    }
    const data = new DataView(memory.buffer, draw.data);
    const samples = settings.surfaceSamples
      ? surfacePatches(data, draw.vertexCount, draw.indexCount, palette)
      : null;
    const bytes = samples ? samples.byteLength : draw.indexCount * RESIDENT_VERTEX_FLOATS * 4;
    if (bytes > GPU_CACHE_BYTES) {
      throw new Error("GPU mesh cache entry exceeds its bound.");
    }
    if (cacheBytes + bytes > GPU_CACHE_BYTES || cache.size >= GPU_CACHE_ENTRIES) {
      clearMeshes();
      entry = null;
    }
    const vertices = samples || new Float32Array(draw.indexCount * RESIDENT_VERTEX_FLOATS);
    for (let triangle = 0; !samples && triangle < draw.indexCount; triangle += 3) {
      const points = [],
        colors = [];
      for (let i = 0; i < 3; i++) {
        const at = data.getUint32(draw.vertexCount * 16 + (triangle + i) * 4, true) * 16;
        points.push([0, 1, 2].map((axis) => data.getFloat32(at + axis * 4, true)));
        const color = data.getUint32(at + 12, true);
        colors.push(
          palette
            ? new DataView(palette.buffer, palette.byteOffset, palette.byteLength).getUint32(
                color * 4,
                true,
              )
            : color,
        );
      }
      for (let i = 0; i < 3; i++) {
        const at = (triangle + i) * RESIDENT_VERTEX_FLOATS;
        for (let axis = 0; axis < 3; axis++) {
          vertices[at + axis] = points[i][axis];
          vertices[at + axis + 3] = ((colors[i] >>> (axis * 8)) & 255) / 255;
          vertices[at + axis + 6] = points[1][axis] - points[0][axis];
          vertices[at + axis + 9] = points[2][axis] - points[0][axis];
        }
      }
    }
    const buffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
    gl.bufferData(gl.ARRAY_BUFFER, vertices, gl.STATIC_DRAW);
    if (gl.getError() !== gl.NO_ERROR) {
      gl.deleteBuffer(buffer);
      throw new Error("GPU mesh upload failed.");
    }
    if (entry) {
      gl.deleteBuffer(entry.buffer);
      cacheBytes -= entry.bytes;
    }
    const result = {
      buffer,
      bytes,
      count: vertices.length / RESIDENT_VERTEX_FLOATS,
      palette: palette?.slice(),
    };
    cache.set(key, result);
    cacheBytes += bytes;
    metrics.cacheBytes = cacheBytes;
    metrics.meshUploads++;
    metrics.uploadBytes += bytes;
    return result;
  };
  const allocate = (t, w, h, depth = false, bytes = null, mask = false) => {
    gl.bindTexture(gl.TEXTURE_2D, t);
    const format = mask ? gl.RED : depth ? gl.DEPTH_COMPONENT : gl.RGBA;
    const type = depth ? gl.FLOAT : gl.UNSIGNED_BYTE;
    const previous = textureStorage.get(t);
    const key = `${w}/${h}/${format}`;
    if (previous?.key === key) {
      if (bytes) {
        gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, 0, w, h, format, type, bytes);
      }
    } else {
      gl.texImage2D(
        gl.TEXTURE_2D,
        0,
        mask ? gl.R8 : depth ? gl.DEPTH_COMPONENT32F : gl.RGBA8,
        w,
        h,
        0,
        format,
        type,
        bytes,
      );
      const size = w * h * (mask ? 1 : 4);
      metrics.textureBytes += size - (previous?.size || 0);
      textureStorage.set(t, { key, size });
    }
    if (bytes) {
      metrics.textureUploadBytes += bytes.byteLength;
    }
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
    metrics,
    queueMesh(
      memory,
      low,
      high,
      data,
      vertexCount,
      indexCount,
      palette,
      model,
      view,
      light,
      ambient,
    ) {
      draws.push({
        low,
        high,
        data,
        vertexCount,
        indexCount,
        palette,
        model: new Float32Array(memory.buffer, model, 16).slice(),
        view: new Float32Array(memory.buffer, view, 16).slice(),
        light: new Float32Array(memory.buffer, light, 3).slice(),
        ambient,
      });
    },
    present(
      memory,
      output,
      preview,
      mask,
      width,
      height,
      availableWidth,
      availableHeight,
      dx,
      dy,
      background,
    ) {
      const scale = preview
        ? Math.max(
            1,
            Math.min(
              6,
              Math.floor(1920 / width),
              Math.floor(1080 / height),
              Math.floor(availableWidth / width),
              Math.floor(availableHeight / height),
            ),
          )
        : 1;
      const smooth = Boolean(preview && scale > 1);
      const w = width * scale,
        h = height * scale;
      if (canvas.width !== w || canvas.height !== h) {
        canvas.width = w;
        canvas.height = h;
      }
      gl.bindVertexArray(vao);
      gl.bindFramebuffer(gl.FRAMEBUFFER, null);
      gl.disable(gl.DEPTH_TEST);
      gl.disable(gl.SCISSOR_TEST);
      gl.useProgram(presentProgram);
      gl.activeTexture(gl.TEXTURE0);
      allocate(
        presentInput[0],
        smooth ? width + 2 : width,
        smooth ? height + 2 : height,
        false,
        new Uint8Array(
          memory.buffer,
          smooth ? preview : output,
          (smooth ? (width + 2) * (height + 2) : width * height) * 4,
        ),
      );
      gl.uniform1i(gl.getUniformLocation(presentProgram, "colorSource"), 0);
      for (const unit of [1, 2]) {
        gl.activeTexture(gl.TEXTURE0 + unit);
        gl.bindTexture(gl.TEXTURE_2D, presentInput[0]);
      }
      gl.uniform1i(gl.getUniformLocation(presentProgram, "depthSource"), 1);
      gl.uniform1i(gl.getUniformLocation(presentProgram, "hudSource"), 2);
      if (smooth) {
        gl.activeTexture(gl.TEXTURE1);
        allocate(
          presentInput[1],
          width,
          height,
          false,
          new Uint8Array(memory.buffer, output, width * height * 4),
        );
        gl.uniform1i(gl.getUniformLocation(presentProgram, "depthSource"), 1);
        gl.activeTexture(gl.TEXTURE2);
        allocate(
          hud,
          width,
          height,
          false,
          new Uint8Array(memory.buffer, mask, width * height),
          true,
        );
        gl.uniform1i(gl.getUniformLocation(presentProgram, "hudSource"), 2);
      }
      gl.uniform2i(gl.getUniformLocation(presentProgram, "logicalSize"), width, height);
      gl.uniform1i(gl.getUniformLocation(presentProgram, "flipY"), 1);
      gl.uniform1i(gl.getUniformLocation(presentProgram, "outputHeight"), h);
      gl.uniform2f(
        gl.getUniformLocation(presentProgram, "residual"),
        Math.round(dx * scale) / scale,
        Math.round(dy * scale) / scale,
      );
      gl.uniform1i(gl.getUniformLocation(presentProgram, "scale"), scale);
      gl.uniform1i(gl.getUniformLocation(presentProgram, "useSmooth"), Number(smooth));
      gl.uniform4f(
        gl.getUniformLocation(presentProgram, "background"),
        (background & 255) / 255,
        ((background >>> 8) & 255) / 255,
        ((background >>> 16) & 255) / 255,
        (background >>> 24) / 255,
      );
      gl.viewport(0, 0, w, h);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
      if (gl.getError() !== gl.NO_ERROR || gl.isContextLost()) {
        throw new Error("GPU presentation failed.");
      }
      return {
        bitmap: canvas.transferToImageBitmap(),
        presentationWidth: w,
        presentationHeight: h,
        smoothPresentation: smooth,
      };
    },
    finish() {
      gl.finish();
    },
    close() {
      clearMeshes();
      const lose = gl.getExtension("WEBGL_lose_context");
      lose?.loseContext();
    },
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
      const batch = draws;
      draws = [];
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
      const program = batch.length ? resident : mesh;
      gl.useProgram(program);
      gl.uniform2f(gl.getUniformLocation(program, "logicalSize"), width, height);
      gl.uniform1i(gl.getUniformLocation(program, "border"), border);
      gl.uniform3f(
        gl.getUniformLocation(program, "fogColor"),
        (fogColor & 255) / 255,
        ((fogColor >>> 8) & 255) / 255,
        ((fogColor >>> 16) & 255) / 255,
      );
      gl.uniform2f(gl.getUniformLocation(program, "fogRange"), fogStart, fogEnd);
      if (batch.length) {
        gl.uniform1i(
          gl.getUniformLocation(program, "surfaceSamples"),
          Number(settings.surfaceSamples),
        );
        gl.bindVertexArray(residentVao);
        for (const draw of batch) {
          if (
            settings.surfaceSamples &&
            (draw.view[3] !== 0 || draw.view[7] !== 0 || draw.view[11] !== 0 || draw.view[15] !== 1)
          ) {
            throw new Error("Surface samples require an orthographic camera.");
          }
          const entry = cachedMesh(memory, draw);
          gl.bindBuffer(gl.ARRAY_BUFFER, entry.buffer);
          for (let i = 0; i < 4; i++) {
            gl.enableVertexAttribArray(i);
            gl.vertexAttribPointer(i, 3, gl.FLOAT, false, RESIDENT_VERTEX_FLOATS * 4, i * 12);
            gl.vertexAttribDivisor(i, settings.surfaceSamples ? SURFACE_POINTS_PER_PATCH : 0);
          }
          gl.uniformMatrix4fv(gl.getUniformLocation(program, "model"), false, draw.model);
          gl.uniformMatrix4fv(gl.getUniformLocation(program, "view"), false, draw.view);
          gl.uniform3fv(gl.getUniformLocation(program, "light"), draw.light);
          gl.uniform1f(gl.getUniformLocation(program, "ambient"), draw.ambient);
          if (settings.surfaceSamples) {
            gl.drawArraysInstanced(gl.TRIANGLE_STRIP, 0, 4, entry.count * SURFACE_POINTS_PER_PATCH);
          } else {
            gl.drawArrays(gl.TRIANGLES, 0, draw.indexCount);
          }
        }
      } else {
        gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
        gl.bufferData(
          gl.ARRAY_BUFFER,
          new Uint8Array(memory.buffer, vertices, count * RASTER_VERTEX_BYTES),
          gl.STREAM_DRAW,
        );
        metrics.uploadBytes += count * RASTER_VERTEX_BYTES;
        gl.drawArrays(gl.TRIANGLES, 0, count);
      }
      gl.bindVertexArray(vao);
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
