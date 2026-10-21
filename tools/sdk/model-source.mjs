import { formatSource } from "../code-tools.mjs";
import { IMPORT_LIMITS } from "./gltf.mjs";

const literal = JSON.stringify;

function formatModel(source, file) {
  if (Buffer.byteLength(source) > IMPORT_LIMITS.sourceBytes) {
    throw new Error("Generated model module exceeds 128 KiB; split or simplify the asset");
  }
  return formatSource(source, file);
}

function luau(model) {
  const geometry = model.primitives
    .map(
      (p) =>
        `{vertices={${p.vertices.map((v) => `{position={${v.position}},uv={${v.uv}},color=${v.color}}`)}},indices={${p.indices}},material=${p.material + 1}}`,
    )
    .join(",\n");
  const locals = model.nodes.map((n) => `{${n.local}}`).join(",\n");
  const parents = model.nodes.map((n) => n.parent + 1);
  const parts = model.nodes.map((n) => `{${n.primitives.map((i) => i + 1)}}`).join(",");
  const materialDefinitions = model.materials
    .map(
      (m) => `{
    width=${m.width},height=${m.height},pixels={${m.pixels}},
    address_u=${literal(m.addressU)},address_v=${literal(m.addressV)},cutoff=${m.cutoff ?? -1}
  }`,
    )
    .join(",\n");
  return formatModel(
    `--!strict
-- Generated model. Reimport the asset to change geometry; animate local transforms in game code.
local byt =  require("@bytorio")
local g, gfx, data = byt.gfx3d, byt.gfx, byt.data
type Matrix = {number}
type Address = "clamp" | "repeat"
type MaterialOptions = {address_u: Address?, address_v: Address?}
export type Instance = {
    alive: boolean,
    meshes: {byt.TexturedMesh},
    materials: {byt.Material},
    textures: {byt.Texture},
}
local geometry = {${geometry}}
local surfaces = {${materialDefinitions}}
local nodeLocals: {Matrix} = {${locals}}
local parents = {${parents}}
local parts = {${parts}}
local names = {${model.nodes.map((n) => literal(n.name))}}
local api = {minimum_sdk=${literal(model.minimumSdk)}, node_count=${model.nodes.length}}

function api.index(name: string): number
    for index, value in names do
        if name == value then return index end
    end
    error("Unknown model node: " .. name)
end

function api.local_transforms(): {Matrix}
    local result = {}
    for _, value in nodeLocals do table.insert(result, table.clone(value)) end
    return result
end

function api.create(): Instance
    assert(byt.capabilities().sdk >= ${model.sdkVersionWord},"Imported model requires SDK ${model.minimumSdk}")
    local instance: Instance = {alive=true,meshes={},materials={},textures={}}
    for _, surface in surfaces do
        local pixels = data.pixels("rgba8", surface.width, surface.height)
        for index, value in surface.pixels do buffer.writeu8(pixels.bytes, index-1, value) end
        local texture = gfx.texture({format="rgba8",width=surface.width,height=surface.height})
        gfx.upload(texture,{x=0,y=0,width=surface.width,height=surface.height},pixels)
        local options: MaterialOptions = {address_u=surface.address_u :: Address,address_v=surface.address_v :: Address}
        local material = if surface.cutoff < 0 then g.material(texture, options) else g.cutout_material(texture,surface.cutoff,options)
        table.insert(instance.textures,texture)
        table.insert(instance.materials,material)
    end
    for _, primitive in geometry do
        table.insert(instance.meshes,g.textured_mesh(primitive.vertices,primitive.indices))
    end
    return instance
end

function api.draw(pass: byt.Pass, instance: Instance, root: Matrix?, locals: {Matrix}?)
    assert(instance.alive,"Model instance is destroyed")
    assert(locals == nil or #locals == #nodeLocals,"Invalid local transform count")
    local world: {Matrix} = {}
    local transforms = locals or nodeLocals
    for index, localModel in transforms do
        local parent = if parents[index] == 0 then (root or g.identity()) else world[parents[index]]
        world[index] = g.multiply(parent,localModel)
        for _, primitive in parts[index] do
            g.draw_textured(pass,instance.meshes[primitive],instance.materials[geometry[primitive].material],world[index])
        end
    end
end

function api.destroy(instance: Instance)
    if not instance.alive then return end
    for _, mesh in instance.meshes do g.destroy(mesh) end
    for _, material in instance.materials do g.destroy(material) end
    for _, texture in instance.textures do gfx.destroy(texture) end
    instance.alive=false
end

return table.freeze(api)
`,
    "model.luau",
  );
}

function odin(model) {
  const meshes = model.primitives
    .map(
      (p, i) => `
    vertices_${i} := [${p.vertices.length}]g.Textured_Vertex{
        ${p.vertices.map((v) => `{{${v.position}},${v.color},{${v.uv}}}`).join(",\n")},
    }
    indices_${i} := [${p.indices.length}]u32{${p.indices}}
    instance.meshes[${i}] = g.textured_mesh(vertices_${i}[:],indices_${i}[:])
  `,
    )
    .join("\n");
  const surfaces = model.materials
    .map(
      (m, i) => `
    pixels_${i} := data.pixels(.RGBA8,${m.width},${m.height})
    bytes_${i} := [${m.pixels.length}]u8{${m.pixels}}
    copy(pixels_${i}.bytes, bytes_${i}[:])
    instance.textures[${i}] = gfx.texture({.RGBA8,${m.width},${m.height}})
    gfx.upload(instance.textures[${i}],{0,0,${m.width},${m.height}},pixels_${i})
    data.free_pixels(&pixels_${i})
    instance.materials[${i}] = g.${m.cutoff === null ? "material" : "cutout_material"}(
        instance.textures[${i}],${m.cutoff === null ? "" : m.cutoff + ","}
        {address_u=.${m.addressU === "clamp" ? "Clamp" : "Repeat"},address_v=.${m.addressV === "clamp" ? "Clamp" : "Repeat"}},
    )
  `,
    )
    .join("\n");
  const draws = model.nodes
    .map((n, i) =>
      n.primitives
        .map(
          (p) =>
            `g.draw_textured(pass,instance.meshes[${p}],instance.materials[${model.primitives[p].material}],world[${i}])`,
        )
        .join("\n"),
    )
    .map((body, i) => `case ${i}:\n${body}`)
    .join("\n");
  return formatModel(
    `// Generated model. Reimport geometry; animate local transforms in game code.
package model

import g "sdk:gfx3d"
import gfx "sdk:gfx"
import data "sdk:data"
import byt "sdk:bytorio"

NODE_COUNT :: ${model.nodes.length}
MINIMUM_SDK :: ${literal(model.minimumSdk)}
Instance :: struct {
    alive: bool,
    meshes: [${model.primitives.length}]g.Textured_Mesh,
    materials: [${model.materials.length}]g.Material,
    textures: [${model.materials.length}]gfx.Texture,
}
names := [NODE_COUNT]string{${model.nodes.map((n) => literal(n.name))}}
parents := [NODE_COUNT]int{${model.nodes.map((n) => n.parent)}}
node_locals := [NODE_COUNT]g.Matrix{${model.nodes.map((n) => `{${n.local}}`).join(",\n")}}

index :: proc(name: string) -> int {
    for value, i in names { if name == value { return i } }
    assert(false,"Unknown model node")
    return 0
}

local_transforms :: proc() -> [NODE_COUNT]g.Matrix { return node_locals }

create :: proc() -> Instance {
    assert(byt.VERSION_WORD >= ${model.sdkVersionWord},"Imported model requires SDK ${model.minimumSdk}")
    instance: Instance
    ${surfaces}
    ${meshes}
    instance.alive = true
    return instance
}

draw :: proc(pass: gfx.Pass, instance: ^Instance, root := g.IDENTITY, locals: []g.Matrix = nil) {
    assert(instance.alive,"Model instance is destroyed")
    assert(len(locals) == 0 || len(locals) == NODE_COUNT,"Invalid local transform count")
    world: [NODE_COUNT]g.Matrix
    for i in 0 ..< NODE_COUNT {
        local_model := locals[i] if len(locals) != 0 else node_locals[i]
        parent := root if parents[i] < 0 else world[parents[i]]
        world[i] = g.multiply(parent,local_model)
        switch i {
            ${draws}
        }
    }
}

destroy :: proc(instance: ^Instance) {
    if !instance.alive { return }
    for mesh in instance.meshes { g.destroy(mesh) }
    for material in instance.materials { g.destroy(material) }
    for texture in instance.textures { gfx.destroy(texture) }
    instance.alive = false
}
`,
    "model.odin",
  );
}

export function modelSources(model) {
  return { "model.luau": luau(model), "model.odin": odin(model) };
}
