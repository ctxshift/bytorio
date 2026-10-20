package gpu

import resources "../../resources"
import gl "vendor:OpenGL"
import sdl "vendor:sdl3"

Device :: struct {
    window:                         ^sdl.Window,
    gl_context:                     sdl.GLContext,
    initialize, mesh, resolve:      u32,
    vao, vertices:                  u32,
    input:                          [2]u32,
    high, low:                      u32,
    high_textures:                  [3]u32,
    low_textures:                   [2]u32,
    width, height, factor, quality: int,
    color, depth:                   []u8,
}
device: Device

open :: proc(quality: int) -> bool {
    device.quality = quality
    if !sdl.InitSubSystem({.VIDEO}) { return false }
    _ = sdl.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, 3)
    _ = sdl.GL_SetAttribute(.CONTEXT_MINOR_VERSION, 3)
    _ = sdl.GL_SetAttribute(.CONTEXT_PROFILE_MASK, i32(sdl.GLProfile.CORE))
    device.window = sdl.CreateWindow("GPU execution device", 1, 1, {.OPENGL, .HIDDEN})
    if device.window == nil { return false }
    device.gl_context = sdl.GL_CreateContext(device.window)
    if device.gl_context == nil {
        close()
        return false
    }
    gl.load_up_to(3, 3, proc(pointer: rawptr, name: cstring) {
        (cast(^rawptr)pointer)^ = rawptr(sdl.GL_GetProcAddress(name))
    })
    prefix :: "#version 330 core\n"
    ok: bool
    device.initialize, ok = gl.load_shaders_source(
        prefix + #load("../fullscreen.vert"),
        prefix + #load("../initialize.frag"),
    )
    if !ok {
        close()
        return false
    }
    device.mesh, ok = gl.load_shaders_source(
        prefix + #load("../mesh.vert"),
        prefix + #load("../mesh.frag"),
    )
    if !ok {
        close()
        return false
    }
    device.resolve, ok = gl.load_shaders_source(
        prefix + #load("../fullscreen.vert"),
        prefix + #load("../resolve.frag"),
    )
    if !ok {
        close()
        return false
    }
    gl.GenVertexArrays(1, &device.vao)
    gl.BindVertexArray(device.vao)
    gl.GenBuffers(1, &device.vertices)
    gl.BindBuffer(gl.ARRAY_BUFFER, device.vertices)
    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(0, 4, gl.FLOAT, gl.FALSE, 28, 0)
    gl.EnableVertexAttribArray(1)
    gl.VertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, 28, 16)
    gl.GenTextures(2, &device.input[0])
    gl.GenTextures(3, &device.high_textures[0])
    gl.GenTextures(2, &device.low_textures[0])
    for texture in device.input { setup_texture(texture) }
    for texture in device.high_textures { setup_texture(texture) }
    for texture in device.low_textures { setup_texture(texture) }
    gl.GenFramebuffers(1, &device.high)
    gl.GenFramebuffers(1, &device.low)
    gl.Disable(gl.DITHER)
    return gl.GetError() == gl.NO_ERROR
}

close :: proc() {
    if device.gl_context != nil {
        _ = sdl.GL_MakeCurrent(device.window, device.gl_context)
        if device.initialize != 0 { gl.DeleteProgram(device.initialize) }
        if device.mesh != 0 { gl.DeleteProgram(device.mesh) }
        if device.resolve != 0 { gl.DeleteProgram(device.resolve) }
        gl.DeleteBuffers(1, &device.vertices)
        gl.DeleteVertexArrays(1, &device.vao)
        gl.DeleteTextures(2, &device.input[0])
        gl.DeleteTextures(3, &device.high_textures[0])
        gl.DeleteTextures(2, &device.low_textures[0])
        gl.DeleteFramebuffers(1, &device.high)
        gl.DeleteFramebuffers(1, &device.low)
        _ = sdl.GL_DestroyContext(device.gl_context)
    }
    if device.window != nil { sdl.DestroyWindow(device.window) }
    delete(device.color)
    delete(device.depth)
    device = {}
}

setup_texture :: proc(texture: u32) {
    gl.BindTexture(gl.TEXTURE_2D, texture)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
}

allocate :: proc(texture: u32, width, height: int, depth := false, data: rawptr = nil) {
    gl.BindTexture(gl.TEXTURE_2D, texture)
    gl.TexImage2D(
        gl.TEXTURE_2D,
        0,
        gl.DEPTH_COMPONENT32F if depth else gl.RGBA8,
        i32(width),
        i32(height),
        0,
        gl.DEPTH_COMPONENT if depth else gl.RGBA,
        gl.FLOAT if depth else gl.UNSIGNED_BYTE,
        data,
    )
}

target :: proc(framebuffer: u32, textures: []u32, width, height: int) -> bool {
    gl.BindFramebuffer(gl.FRAMEBUFFER, framebuffer)
    for texture, i in textures {
        allocate(texture, width, height, i == 2)
        attachment := gl.DEPTH_ATTACHMENT if i == 2 else gl.COLOR_ATTACHMENT0 + u32(i)
        gl.FramebufferTexture2D(gl.FRAMEBUFFER, attachment, gl.TEXTURE_2D, texture, 0)
    }
    attachments := [2]u32{gl.COLOR_ATTACHMENT0, gl.COLOR_ATTACHMENT1}
    gl.DrawBuffers(2, &attachments[0])
    return gl.CheckFramebufferStatus(gl.FRAMEBUFFER) == gl.FRAMEBUFFER_COMPLETE
}

quad :: proc(program, color, depth: u32, factor, width, height: int, border := 0) {
    gl.UseProgram(program)
    gl.ActiveTexture(gl.TEXTURE0)
    gl.BindTexture(gl.TEXTURE_2D, color)
    gl.Uniform1i(gl.GetUniformLocation(program, "colorSource"), 0)
    gl.ActiveTexture(gl.TEXTURE1)
    gl.BindTexture(gl.TEXTURE_2D, depth)
    gl.Uniform1i(gl.GetUniformLocation(program, "depthSource"), 1)
    gl.Uniform1i(gl.GetUniformLocation(program, "factor"), i32(factor))
    gl.Uniform1i(gl.GetUniformLocation(program, "border"), i32(border))
    gl.Viewport(0, 0, i32(width), i32(height))
    gl.DrawArrays(gl.TRIANGLES, 0, 3)
}

raster :: proc(job: resources.Raster_Job) -> bool {
    if !sdl.GL_MakeCurrent(device.window, device.gl_context) { return false }
    w, h := job.width, job.height
    border := 1 if len(job.border) != 0 else 0
    rw, rh := w + border * 2, h + border * 2
    factor := 1
    if device.quality == 2 { factor = 2 }
    if device.quality == 6 { factor = max(1, min(6, 1920 / w, 1080 / h)) }
    factor = max(1, min(factor, 1920 / w, 1080 / h))
    if rw * rh * factor * factor > 1932 * 1092 { return false }
    if device.width != rw || device.height != rh || device.factor != factor {
        if !target(device.high, device.high_textures[:], rw * factor, rh * factor) ||
           !target(device.low, device.low_textures[:], rw, rh) { return false }
        delete(device.color)
        delete(device.depth)
        device.color = make([]u8, rw * rh * 4)
        device.depth = make([]u8, rw * rh * 4)
        device.width, device.height, device.factor = rw, rh, factor
    }
    gl.BindVertexArray(device.vao)
    gl.Disable(gl.SCISSOR_TEST)
    gl.BindFramebuffer(gl.FRAMEBUFFER, device.high)
    gl.Enable(gl.DEPTH_TEST)
    gl.DepthFunc(gl.ALWAYS)
    gl.ActiveTexture(gl.TEXTURE0)
    allocate(device.input[0], w, h, data = raw_data(job.color))
    allocate(device.input[1], w, h, data = raw_data(job.depth))
    quad(
        device.initialize,
        device.input[0],
        device.input[1],
        factor,
        rw * factor,
        rh * factor,
        border,
    )
    gl.DepthFunc(gl.LESS)
    gl.Enable(gl.SCISSOR_TEST)
    x0, y0 := max(0, int(job.clip[0])), max(0, int(job.clip[1]))
    x1, y1 := min(w, int(job.clip[0] + job.clip[2])), min(h, int(job.clip[1] + job.clip[3]))
    if border !=
       0 { gl.Disable(gl.SCISSOR_TEST) } else { gl.Scissor(i32(x0 * factor), i32(y0 * factor), i32(max(0, x1 - x0) * factor), i32(max(0, y1 - y0) * factor)) }
    gl.UseProgram(device.mesh)
    gl.Uniform2f(gl.GetUniformLocation(device.mesh, "logicalSize"), f32(w), f32(h))
    gl.Uniform1i(gl.GetUniformLocation(device.mesh, "border"), i32(border))
    fog := job.fog_color
    gl.Uniform3f(
        gl.GetUniformLocation(device.mesh, "fogColor"),
        f32(fog & 255) / 255,
        f32((fog >> 8) & 255) / 255,
        f32((fog >> 16) & 255) / 255,
    )
    gl.Uniform2f(gl.GetUniformLocation(device.mesh, "fogRange"), job.fog_start, job.fog_end)
    gl.BindBuffer(gl.ARRAY_BUFFER, device.vertices)
    gl.BufferData(gl.ARRAY_BUFFER, len(job.vertices), raw_data(job.vertices), gl.STREAM_DRAW)
    gl.DrawArrays(gl.TRIANGLES, 0, i32(len(job.vertices) / resources.RASTER_VERTEX_BYTES))
    gl.Disable(gl.SCISSOR_TEST)
    gl.Disable(gl.DEPTH_TEST)
    gl.BindFramebuffer(gl.FRAMEBUFFER, device.low)
    quad(device.resolve, device.high_textures[0], device.high_textures[1], factor, rw, rh)
    gl.ReadBuffer(gl.COLOR_ATTACHMENT0)
    gl.ReadPixels(0, 0, i32(rw), i32(rh), gl.RGBA, gl.UNSIGNED_BYTE, raw_data(device.color))
    gl.ReadBuffer(gl.COLOR_ATTACHMENT1)
    gl.ReadPixels(0, 0, i32(rw), i32(rh), gl.RGBA, gl.UNSIGNED_BYTE, raw_data(device.depth))
    if gl.GetError() != gl.NO_ERROR { return false }
    for y in 0 ..< h {
        source := ((y + border) * rw + border) * 4
        copy(job.color[y * w * 4:][:w * 4], device.color[source:][:w * 4])
        copy(job.depth[y * w * 4:][:w * 4], device.depth[source:][:w * 4])
    }
    copy(job.border, device.color)
    return true
}
