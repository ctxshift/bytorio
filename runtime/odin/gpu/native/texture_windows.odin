package gpu

import resources "../../resources"
import gl "vendor:OpenGL"

GPU_TEXTURE_CACHE_BYTES :: 32 * 1024 * 1024

Cached_Texture :: struct {
    texture: u32,
    bytes:   int,
}

clear_textures :: proc() {
    for _, entry in device.material_cache {
        texture := entry.texture
        gl.DeleteTextures(1, &texture)
        delete_key(&device.texture_storage, texture)
    }
    delete(device.material_cache)
    device.material_cache = nil
    device.material_cache_bytes = 0
}

bind_material :: proc(program: u32, view: resources.Texture_View) -> bool {
    textured := len(view.pixels) != 0
    gl.Uniform1i(gl.GetUniformLocation(program, "useTexture"), 1 if textured else 0)
    gl.Uniform1i(gl.GetUniformLocation(program, "materialTexture"), 2)
    gl.ActiveTexture(gl.TEXTURE2)
    if !textured {
        gl.BindTexture(gl.TEXTURE_2D, device.input[0])
        return true
    }
    entry, exists := device.material_cache[view.version]
    if exists {
        device.texture_cache_hits += 1
    } else {
        size := len(view.pixels)
        if view.version == 0 || size > GPU_TEXTURE_CACHE_BYTES { return false }
        if device.material_cache_bytes + size > GPU_TEXTURE_CACHE_BYTES ||
           len(device.material_cache) >= GPU_CACHE_ENTRIES { clear_textures() }
        texture: u32
        gl.GenTextures(1, &texture)
        setup_texture(texture)
        allocate(texture, int(view.width), int(view.height), data = raw_data(view.pixels))
        if gl.GetError() != gl.NO_ERROR {
            gl.DeleteTextures(1, &texture)
            delete_key(&device.texture_storage, texture)
            return false
        }
        entry = {texture, size}
        if device.material_cache == nil { device.material_cache = make(map[u64]Cached_Texture) }
        device.material_cache[view.version] = entry
        device.material_cache_bytes += size
        device.texture_uploads += 1
        device.texture_upload_bytes += u64(size)
    }
    gl.BindTexture(gl.TEXTURE_2D, entry.texture)
    gl.Uniform2i(
        gl.GetUniformLocation(program, "textureAddress"),
        i32(view.address_u),
        i32(view.address_v),
    )
    return true
}

texture_statistics :: proc() -> [3]u64 {
    return {device.texture_uploads, device.texture_cache_hits, device.texture_upload_bytes}
}

texture_cached_bytes :: proc() -> int { return device.material_cache_bytes }
