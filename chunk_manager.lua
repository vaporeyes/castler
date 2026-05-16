-- ABOUTME: Partitions the voxel world into fixed-size 3D chunks, each owning
-- ABOUTME: its own Love2D Mesh. Edits mark affected chunks dirty and only
-- ABOUTME: those rebuild, so large worlds stay editable in real time.

local ChunkManager = {}
ChunkManager.__index = ChunkManager

local CHUNK_SIZE = 16

local VERTEX_FORMAT = {
    {"VertexPosition", "float", 3},
    {"VertexColor",    "float", 4},
}

-- Directional shade: a sun gives each face a brightness from
-- ambient + diffuse * max(0, dot(faceNormal, sunDir)). The sun direction is
-- mutable (see ChunkManager:setSun); changing it re-bakes all chunk meshes
-- since lighting is baked into vertex colors at mesh-gen time.
local SUN_DIR = {0.40, 0.86, 0.30}  -- points up-and-toward-front
do
    local m = math.sqrt(SUN_DIR[1]^2 + SUN_DIR[2]^2 + SUN_DIR[3]^2)
    SUN_DIR[1], SUN_DIR[2], SUN_DIR[3] = SUN_DIR[1]/m, SUN_DIR[2]/m, SUN_DIR[3]/m
end
local AMBIENT = 0.48
local DIFFUSE = 0.52

-- Ambient occlusion: per-vertex darkening from how many of the three voxels
-- around that corner (on the face's outward side) are solid. Classic
-- "Minecraft AO" - levels 0..3 map to these multipliers.
local AO_MUL = {[0] = 0.42, [1] = 0.62, [2] = 0.81, [3] = 1.0}

local function aoLevel(s1, s2, c)
    if s1 and s2 then return 0 end  -- pinched corner, fully occluded
    local n = (s1 and 1 or 0) + (s2 and 1 or 0) + (c and 1 or 0)
    return 3 - n
end

-- Base faces with their winding preserved exactly (do not reorder verts -
-- index emission below depends on this CCW order for correct culling).
local FACE_DEFS = {
    {n = { 1, 0, 0}, verts = {{1,0,0},{1,0,1},{1,1,1},{1,1,0}}},
    {n = {-1, 0, 0}, verts = {{0,0,1},{0,0,0},{0,1,0},{0,1,1}}},
    {n = { 0, 1, 0}, verts = {{0,1,0},{0,1,1},{1,1,1},{1,1,0}}},
    {n = { 0,-1, 0}, verts = {{0,0,1},{0,0,0},{1,0,0},{1,0,1}}},
    {n = { 0, 0, 1}, verts = {{1,0,1},{0,0,1},{0,1,1},{1,1,1}}},
    {n = { 0, 0,-1}, verts = {{0,0,0},{1,0,0},{1,1,0},{0,1,0}}},
}

-- Build the runtime FACES table: per-face directional shade plus, for each of
-- the 4 vertices, the three block-relative offsets (side1, side2, corner) to
-- sample for ambient occlusion.
-- Geometry/AO is sun-independent and built once. `shade` is filled in by
-- computeFaceShades() and re-filled whenever the sun moves.
local FACES = {}
for _, fd in ipairs(FACE_DEFS) do
    local n = fd.n

    -- The two axes the face lies in (where the normal component is zero).
    local axisA, axisB
    for a = 1, 3 do
        if n[a] == 0 then
            if not axisA then axisA = a else axisB = a end
        end
    end

    local face = { dx = n[1], dy = n[2], dz = n[3], shade = 1, verts = {}, ao = {} }
    for v = 1, 4 do
        local vp = fd.verts[v]
        face.verts[v] = vp
        local sA = (vp[axisA] == 1) and 1 or -1
        local sB = (vp[axisB] == 1) and 1 or -1
        local o1 = {n[1], n[2], n[3]}; o1[axisA] = o1[axisA] + sA
        local o2 = {n[1], n[2], n[3]}; o2[axisB] = o2[axisB] + sB
        local oc = {n[1], n[2], n[3]}; oc[axisA] = oc[axisA] + sA; oc[axisB] = oc[axisB] + sB
        face.ao[v] = { o1, o2, oc }
    end
    FACES[#FACES + 1] = face
end

-- (Re)compute per-face directional brightness from the current SUN_DIR.
local function computeFaceShades()
    for i = 1, #FACES do
        local f = FACES[i]
        local d = f.dx*SUN_DIR[1] + f.dy*SUN_DIR[2] + f.dz*SUN_DIR[3]
        if d < 0 then d = 0 end
        f.shade = math.min(1, AMBIENT + DIFFUSE * d)
    end
end
computeFaceShades()

local NEIGHBOR_OFFSETS = {
    {1,0,0}, {-1,0,0}, {0,1,0}, {0,-1,0}, {0,0,1}, {0,0,-1},
}

local function loadShader()
    return love.graphics.newShader(love.filesystem.read("shaders/voxel.glsl"))
end

local function newChunk(cx, cy, cz)
    return {
        cx = cx, cy = cy, cz = cz,
        x0 = cx * CHUNK_SIZE + 1,
        y0 = cy * CHUNK_SIZE + 1,
        z0 = cz * CHUNK_SIZE + 1,
        mesh = nil,
        meshCapacity = 0,
        vertexCount = 0,
        indexCount = 0,
        dirty = true,
        vertices = {},
        indices  = {},
    }
end

function ChunkManager.new(world)
    local self = setmetatable({}, ChunkManager)
    self.world = world
    self.shader = loadShader()
    self.chunkSize = CHUNK_SIZE

    self.chunkW = math.ceil(world.width  / CHUNK_SIZE)
    self.chunkH = math.ceil(world.height / CHUNK_SIZE)
    self.chunkD = math.ceil(world.depth  / CHUNK_SIZE)
    self.chunkCount = self.chunkW * self.chunkH * self.chunkD

    self.chunks = {}
    self.dirtyChunks = {}
    for cz = 0, self.chunkD - 1 do
        for cy = 0, self.chunkH - 1 do
            for cx = 0, self.chunkW - 1 do
                local key = self:chunkKey(cx, cy, cz)
                self.chunks[key] = newChunk(cx, cy, cz)
                self.dirtyChunks[key] = true
            end
        end
    end

    self:flushDirty()
    return self
end

function ChunkManager:markChunkDirty(cx, cy, cz)
    local key = self:chunkKey(cx, cy, cz)
    local chunk = self.chunks[key]
    if not chunk then return end
    if chunk.dirty then
        self.dirtyChunks[key] = true
        return
    end
    chunk.dirty = true
    self.dirtyChunks[key] = true
end

function ChunkManager:chunkKey(cx, cy, cz)
    return ((cz * self.chunkH) + cy) * self.chunkW + cx
end

function ChunkManager:chunkCoordsOf(x, y, z)
    return math.floor((x - 1) / CHUNK_SIZE),
           math.floor((y - 1) / CHUNK_SIZE),
           math.floor((z - 1) / CHUNK_SIZE)
end

-- Mark the chunk containing (x,y,z) as dirty. Also marks face-adjacent chunks
-- when the edit lies on a chunk boundary, because their face culling depends
-- on what sits in the cell across the seam.
function ChunkManager:markDirty(x, y, z)
    if not self.world:inBounds(x, y, z) then return end
    local cx, cy, cz = self:chunkCoordsOf(x, y, z)
    self:markChunkDirty(cx, cy, cz)

    for i = 1, 6 do
        local o = NEIGHBOR_OFFSETS[i]
        local nx, ny, nz = x + o[1], y + o[2], z + o[3]
        if self.world:inBounds(nx, ny, nz) then
            local ncx, ncy, ncz = self:chunkCoordsOf(nx, ny, nz)
            if ncx ~= cx or ncy ~= cy or ncz ~= cz then
                self:markChunkDirty(ncx, ncy, ncz)
            end
        end
    end
end

local FACE_SPANS = {
    {u = 2, v = 3}, {u = 2, v = 3},
    {u = 1, v = 3}, {u = 1, v = 3},
    {u = 1, v = 2}, {u = 1, v = 2},
}

local function setCoord(out, axis, value)
    out[axis] = value
end

local function faceAoKey(world, face, x, y, z)
    local key = 0
    for v = 1, 4 do
        local sample = face.ao[v]
        local o1, o2, oc = sample[1], sample[2], sample[3]
        local s1 = world:getBlock(x+o1[1], y+o1[2], z+o1[3]) ~= 0
        local s2 = world:getBlock(x+o2[1], y+o2[2], z+o2[3]) ~= 0
        local sc = world:getBlock(x+oc[1], y+oc[2], z+oc[3]) ~= 0
        key = key * 4 + aoLevel(s1, s2, sc)
    end
    return key
end

local function addMergedFace(world, palette, verts, idxs, faceIndex, x, y, z, sizes, vCount, iCount, vIndex)
    local face = FACES[faceIndex]
    local id = world:getBlock(x, y, z)
    local col = palette[id] or {1, 0, 1}
    local shade = face.shade
    local fr, fg, fb = col[1] * shade, col[2] * shade, col[3] * shade
    local ao = face.ao
    local m1, m2, m3, m4

    local function scaledVertex(vp)
        if faceIndex == 1 then
            return x, y - 1 + vp[2] * sizes[2], z - 1 + vp[3] * sizes[3]
        elseif faceIndex == 2 then
            return x - 1, y - 1 + vp[2] * sizes[2], z - 1 + vp[3] * sizes[3]
        elseif faceIndex == 3 then
            return x - 1 + vp[1] * sizes[1], y, z - 1 + vp[3] * sizes[3]
        elseif faceIndex == 4 then
            return x - 1 + vp[1] * sizes[1], y - 1, z - 1 + vp[3] * sizes[3]
        elseif faceIndex == 5 then
            return x - 1 + vp[1] * sizes[1], y - 1 + vp[2] * sizes[2], z
        else
            return x - 1 + vp[1] * sizes[1], y - 1 + vp[2] * sizes[2], z - 1
        end
    end

    for v = 1, 4 do
        local vp = face.verts[v]
        local sx = x + ((sizes[1] > 1 and vp[1] == 1) and (sizes[1] - 1) or 0)
        local sy = y + ((sizes[2] > 1 and vp[2] == 1) and (sizes[2] - 1) or 0)
        local sz = z + ((sizes[3] > 1 and vp[3] == 1) and (sizes[3] - 1) or 0)
        local sample = ao[v]
        local o1, o2, oc = sample[1], sample[2], sample[3]
        local s1 = world:getBlock(sx+o1[1], sy+o1[2], sz+o1[3]) ~= 0
        local s2 = world:getBlock(sx+o2[1], sy+o2[2], sz+o2[3]) ~= 0
        local sc = world:getBlock(sx+oc[1], sy+oc[2], sz+oc[3]) ~= 0
        local m = AO_MUL[aoLevel(s1, s2, sc)]
        if     v == 1 then m1 = m
        elseif v == 2 then m2 = m
        elseif v == 3 then m3 = m
        else               m4 = m end
        local vx, vy, vz = scaledVertex(vp)
        vCount = vCount + 1
        verts[vCount] = {vx, vy, vz, fr * m, fg * m, fb * m, 1}
    end

    if m1 + m3 < m2 + m4 then
        idxs[iCount + 1] = vIndex + 2
        idxs[iCount + 2] = vIndex + 3
        idxs[iCount + 3] = vIndex + 4
        idxs[iCount + 4] = vIndex + 2
        idxs[iCount + 5] = vIndex + 4
        idxs[iCount + 6] = vIndex + 1
    else
        idxs[iCount + 1] = vIndex + 1
        idxs[iCount + 2] = vIndex + 2
        idxs[iCount + 3] = vIndex + 3
        idxs[iCount + 4] = vIndex + 1
        idxs[iCount + 5] = vIndex + 3
        idxs[iCount + 6] = vIndex + 4
    end
    return vCount, iCount + 6, vIndex + 4
end

function ChunkManager:regenerateChunk(chunk)
    local world = self.world
    local palette = world.PALETTE

    local verts = chunk.vertices
    local idxs  = chunk.indices
    local vCount, iCount, vIndex = 0, 0, 0

    local x0 = chunk.x0
    local y0 = chunk.y0
    local z0 = chunk.z0
    local xMax = math.min(x0 + CHUNK_SIZE - 1, world.width)
    local yMax = math.min(y0 + CHUNK_SIZE - 1, world.height)
    local zMax = math.min(z0 + CHUNK_SIZE - 1, world.depth)
    local mins = {x0, y0, z0}
    local maxs = {xMax, yMax, zMax}
    local maskId = {}
    local maskAo = {}
    local coord = {}
    local sizes = {}

    for faceIndex = 1, 6 do
        local face = FACES[faceIndex]
        local span = FACE_SPANS[faceIndex]
        local normalAxis
        if face.dx ~= 0 then normalAxis = 1
        elseif face.dy ~= 0 then normalAxis = 2
        else normalAxis = 3 end

        local uAxis, vAxis = span.u, span.v
        local uMin, uMax = mins[uAxis], maxs[uAxis]
        local vMin, vMax = mins[vAxis], maxs[vAxis]
        local uCount = uMax - uMin + 1
        local vCount2 = vMax - vMin + 1

        for w = mins[normalAxis], maxs[normalAxis] do
            for i = 1, uCount * vCount2 do
                maskId[i] = nil
                maskAo[i] = nil
            end

            for vv = vMin, vMax do
                for uu = uMin, uMax do
                    setCoord(coord, normalAxis, w)
                    setCoord(coord, uAxis, uu)
                    setCoord(coord, vAxis, vv)
                    local x, y, z = coord[1], coord[2], coord[3]
                    local id = world:getBlock(x, y, z)
                    if id ~= 0 and world:getBlock(x + face.dx, y + face.dy, z + face.dz) == 0 then
                        local idx = (vv - vMin) * uCount + (uu - uMin) + 1
                        maskId[idx] = id
                        maskAo[idx] = faceAoKey(world, face, x, y, z)
                    end
                end
            end

            for vv = vMin, vMax do
                local u = uMin
                while u <= uMax do
                    local idx = (vv - vMin) * uCount + (u - uMin) + 1
                    local id = maskId[idx]
                    if id then
                        local aoKey = maskAo[idx]
                        local rectW = 1
                        while u + rectW <= uMax do
                            local nextIdx = (vv - vMin) * uCount + (u + rectW - uMin) + 1
                            if maskId[nextIdx] ~= id or maskAo[nextIdx] ~= aoKey then break end
                            rectW = rectW + 1
                        end

                        local rectH = 1
                        local canGrow = true
                        while vv + rectH <= vMax and canGrow do
                            for du = 0, rectW - 1 do
                                local rowIdx = (vv + rectH - vMin) * uCount + (u + du - uMin) + 1
                                if maskId[rowIdx] ~= id or maskAo[rowIdx] ~= aoKey then
                                    canGrow = false
                                    break
                                end
                            end
                            if canGrow then rectH = rectH + 1 end
                        end

                        for dv = 0, rectH - 1 do
                            for du = 0, rectW - 1 do
                                local clearIdx = (vv + dv - vMin) * uCount + (u + du - uMin) + 1
                                maskId[clearIdx] = nil
                                maskAo[clearIdx] = nil
                            end
                        end

                        setCoord(coord, normalAxis, w)
                        setCoord(coord, uAxis, u)
                        setCoord(coord, vAxis, vv)
                        sizes[1], sizes[2], sizes[3] = 1, 1, 1
                        sizes[uAxis] = rectW
                        sizes[vAxis] = rectH
                        vCount, iCount, vIndex = addMergedFace(
                            world, palette, verts, idxs, faceIndex,
                            coord[1], coord[2], coord[3], sizes,
                            vCount, iCount, vIndex)
                        u = u + rectW
                    else
                        u = u + 1
                    end
                end
            end
        end
    end

    for i = vCount + 1, #verts do verts[i] = nil end
    for i = iCount + 1, #idxs  do idxs[i]  = nil end

    chunk.vertexCount = vCount
    chunk.indexCount  = iCount
    chunk.dirty = false
    self.dirtyChunks[self:chunkKey(chunk.cx, chunk.cy, chunk.cz)] = nil

    if vCount == 0 then
        chunk.mesh = nil
        return
    end

    if chunk.mesh == nil or chunk.meshCapacity < vCount then
        chunk.mesh = love.graphics.newMesh(VERTEX_FORMAT, verts, "triangles", "dynamic")
        chunk.meshCapacity = vCount
    else
        chunk.mesh:setVertices(verts, 1, vCount)
    end
    chunk.mesh:setVertexMap(idxs)
    chunk.mesh:setDrawRange(1, iCount)
end

-- Force every chunk to rebuild on the next flush. Used after bulk world
-- mutations (e.g. importing a level) where per-cell markDirty would be wasteful.
function ChunkManager:markAllDirty()
    for key, chunk in pairs(self.chunks) do
        chunk.dirty = true
        self.dirtyChunks[key] = true
    end
end

-- Move the sun. Re-bakes every chunk mesh (lighting lives in vertex colors),
-- so this is a bulk op on the order of a castle regen, not a per-frame change.
function ChunkManager:setSun(x, y, z)
    local m = math.sqrt(x*x + y*y + z*z)
    if m < 1e-6 then return end
    SUN_DIR[1], SUN_DIR[2], SUN_DIR[3] = x/m, y/m, z/m
    computeFaceShades()
    self:markAllDirty()
    self:flushDirty()
end

function ChunkManager:flushDirty()
    for key in pairs(self.dirtyChunks) do
        local chunk = self.chunks[key]
        if chunk and chunk.dirty then
            self:regenerateChunk(chunk)
        else
            self.dirtyChunks[key] = nil
        end
    end
end

-- DOOM-style "diminished lighting" via linear fog from u_fogStart..u_fogEnd.
-- Fog color matches the scene clear color so geometry dissolves into the
-- background instead of revealing a hard horizon.
ChunkManager.FOG_COLOR = {0.14, 0.16, 0.23}
ChunkManager.FOG_START = 90
ChunkManager.FOG_END   = 280

function ChunkManager:draw(viewMatrix, projectionMatrix)
    love.graphics.setDepthMode("less", true)
    love.graphics.setShader(self.shader)
    self.shader:send("u_view",       "column", viewMatrix)
    self.shader:send("u_proj",       "column", projectionMatrix)
    self.shader:send("u_fogColor",   self.FOG_COLOR)
    self.shader:send("u_fogStart",   self.FOG_START)
    self.shader:send("u_fogEnd",     self.FOG_END)
    self.shader:send("u_fogEnabled", 1.0)

    for _, chunk in pairs(self.chunks) do
        if chunk.mesh then
            love.graphics.draw(chunk.mesh)
        end
    end

    love.graphics.setShader()
    love.graphics.setDepthMode()
end

function ChunkManager:getStats()
    local verts, tris, drawn = 0, 0, 0
    for _, chunk in pairs(self.chunks) do
        verts = verts + chunk.vertexCount
        tris  = tris  + chunk.indexCount / 3
        if chunk.mesh then drawn = drawn + 1 end
    end
    return verts, tris, drawn, self.chunkCount
end

return ChunkManager
