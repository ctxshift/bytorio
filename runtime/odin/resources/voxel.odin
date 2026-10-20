package resources

import w "../resource_protocol"

voxel_palette_write :: proc(t: ^Transaction, palette, offset: u32, data: []u8) -> bool {
    for slot in t.slots^ {
        if slot.kind != .Voxel || slot.link != palette {
            continue
        }

        size := int(slot.width) * int(slot.height) * int(slot.volume_depth)
        t.voxel_palette_cells += u64(size)
        if t.voxel_palette_cells > w.maxVoxelCellsPerCommit {
            return fail(t.registry, "voxel palette validation work limit exceeded")
        }

        for cell in slot.data[:size] {
            at := int(cell) * 4 - int(offset)
            if cell != 0 && at >= 0 && at + 4 <= len(data) && u32le(data, at) >> 24 != 255 {
                return fail(t.registry, "palette edit makes occupied voxels transparent")
            }
        }
    }

    return true
}

// Source cells and the derived indexed surface share a single versioned allocation.
// The prototype bounds full-volume rebuilds; chunked rebuilds can replace this later.
VOXEL_NEIGHBORS :: [6][3]int {
    {-1, 0, 0},
    {1, 0, 0},
    {0, -1, 0},
    {0, 1, 0},
    {0, 0, -1},
    {0, 0, 1},
}

VOXEL_CORNERS := [6][4][3]int {
    {
        {0, 0, 0},
        {0, 0, 1},
        {0, 1, 1},
        {0, 1, 0},
    },
    {
        {1, 0, 1},
        {1, 0, 0},
        {1, 1, 0},
        {1, 1, 1},
    },
    {
        {0, 0, 1},
        {0, 0, 0},
        {1, 0, 0},
        {1, 0, 1},
    },
    {
        {0, 1, 0},
        {0, 1, 1},
        {1, 1, 1},
        {1, 1, 0},
    },
    {
        {1, 0, 0},
        {0, 0, 0},
        {0, 1, 0},
        {1, 1, 0},
    },
    {
        {0, 0, 1},
        {1, 0, 1},
        {1, 1, 1},
        {0, 1, 1},
    },
}

voxel_cell :: proc(cells: []u8, dims: [3]int, x, y, z: int) -> u8 {
    if x < 0 || y < 0 || z < 0 || x >= dims[0] || y >= dims[1] || z >= dims[2] {
        return 0
    }

    return cells[(z * dims[1] + y) * dims[0] + x]
}

voxel_build :: proc(
    t: ^Transaction,
    slot: ^Slot,
    dims: [3]int,
    palette: u32,
    cells: []u8,
) -> bool {
    count := dims[0] * dims[1] * dims[2]
    if t.voxel_cells + u64(count) > w.maxVoxelCellsPerCommit {
        return fail(t.registry, "voxel rebuild work limit exceeded")
    }

    colors := lookup(t, palette, .Palette)
    if colors == nil {
        return fail(t.registry, "invalid voxel palette")
    }

    faces := 0
    for z in 0 ..< dims[2] {
        for y in 0 ..< dims[1] {
            for x in 0 ..< dims[0] {
                cell := voxel_cell(cells, dims, x, y, z)
                if cell == 0 {
                    continue
                }

                if u32le(colors.data, int(cell) * 4) >> 24 != 255 {
                    return fail(t.registry, "occupied voxel colors must be opaque")
                }

                for d in VOXEL_NEIGHBORS {
                    if voxel_cell(cells, dims, x + d[0], y + d[1], z + d[2]) == 0 {
                        faces += 1
                    }
                }
            }
        }
    }

    if faces > w.maxVoxelFaces {
        return fail(t.registry, "voxel surface limit exceeded")
    }

    offset := (count + 3) &~ 3
    vertex_bytes := faces * 4 * w.meshVertexBytes
    bytes, ok := allocate(t, offset + vertex_bytes + faces * 6 * w.meshIndexBytes)
    if !ok {
        return false
    }

    copy(bytes, cells)
    t.copy_bytes += u64(count)
    face := 0
    for z in 0 ..< dims[2] {
        for y in 0 ..< dims[1] {
            for x in 0 ..< dims[0] {
                cell := voxel_cell(cells, dims, x, y, z)
                if cell == 0 {
                    continue
                }

                for d, dir in VOXEL_NEIGHBORS {
                    if voxel_cell(cells, dims, x + d[0], y + d[1], z + d[2]) != 0 {
                        continue
                    }

                    corners := VOXEL_CORNERS[dir]
                    for corner, i in corners {
                        at := offset + (face * 4 + i) * w.meshVertexBytes
                        putf(bytes, at, f64(x + corner[0]))
                        putf(bytes, at + 4, f64(y + corner[1]))
                        putf(bytes, at + 8, f64(z + corner[2]))
                        put32(bytes, at + w.meshColorOffset, u32(cell))
                    }

                    order := [6]u32{0, 1, 2, 0, 2, 3}

                    for index, i in order {
                        put32(
                            bytes,
                            offset + vertex_bytes + (face * 6 + i) * 4,
                            u32(face * 4) + index,
                        )
                    }

                    face += 1
                }
            }
        }
    }

    slot.kind, slot.width, slot.height, slot.volume_depth =
        .Voxel, u32(dims[0]), u32(dims[1]), u32(dims[2])
    slot.link, slot.mesh_offset, slot.vertex_count, slot.index_count =
        palette, u32(offset), u32(faces * 4), u32(faces * 6)
    slot.data = bytes
    slot.gpu_version = mesh_version(t.registry)
    t.voxel_cells += u64(count)
    t.voxel_faces += u64(faces)
    t.voxel_rebuilds += 1
    return true
}

voxel_create :: proc(t: ^Transaction, slot: ^Slot, descriptor: [8]u32, cells: []u8) -> bool {
    a := descriptor
    for axis in a[:3] {
        if axis == 0 || axis > w.maxVoxelAxis {
            return fail(t.registry, "invalid voxel dimensions")
        }
    }

    if !padding_zero(a[4:]) || len(cells) != int(a[0] * a[1] * a[2]) {
        return fail(t.registry, "invalid voxel data")
    }

    return voxel_build(t, slot, {int(a[0]), int(a[1]), int(a[2])}, a[3], cells)
}

voxel_edit :: proc(t: ^Transaction, id: u32, descriptor: [8]u32, data: []u8) -> bool {
    a := descriptor
    slot := lookup(t, id, .Voxel)
    if slot == nil || !padding_zero(a[6:]) {
        return fail(t.registry, "invalid voxel edit handle or padding")
    }

    dims := [3]int{int(slot.width), int(slot.height), int(slot.volume_depth)}

    for axis in 0 ..< 3 {
        if a[axis + 3] == 0 || u64(a[axis]) + u64(a[axis + 3]) > u64(dims[axis]) {
            return fail(t.registry, "voxel edit outside volume")
        }
    }

    if u64(a[3]) * u64(a[4]) * u64(a[5]) != u64(len(data)) {
        return fail(t.registry, "invalid voxel edit byte length")
    }

    cells, ok := allocate(t, dims[0] * dims[1] * dims[2])
    if !ok {
        return false
    }

    defer {
        t.retained -= len(cells)
        delete(cells)
    }

    copy(cells, slot.data)
    t.copy_bytes += u64(len(cells))
    for z in 0 ..< int(a[5]) {
        for y in 0 ..< int(a[4]) {
            dst := ((z + int(a[2])) * dims[1] + y + int(a[1])) * dims[0] + int(a[0])
            src := (z * int(a[4]) + y) * int(a[3])
            copy(cells[dst:][:int(a[3])], data[src:][:int(a[3])])
        }
    }

    old := slot.data
    original := t.registry.slots[(id & w.handleIndexMask) - 1].data
    if !voxel_build(t, slot, dims, slot.link, cells) {
        return false
    }

    if raw_data(old) != raw_data(original) {
        t.retained -= len(old)
        delete(old)
    }

    return true
}
