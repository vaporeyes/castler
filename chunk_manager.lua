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

local FACE_SHADE = {
    px = 0.80, nx = 0.80,
    py = 1.00, ny = 0.55,
    pz = 0.65, nz = 0.65,
}

local FACES = {
    {dx= 1, dy= 0, dz= 0, shade=FACE_SHADE.px, verts={{1,0,0},{1,0,1},{1,1,1},{1,1,0}}},
    {dx=-1, dy= 0, dz= 0, shade=FACE_SHADE.nx, verts={{0,0,1},{0,0,0},{0,1,0},{0,1,1}}},
    {dx= 0, dy= 1, dz= 0, shade=FACE_SHADE.py, verts={{0,1,0},{0,1,1},{1,1,1},{1,1,0}}},
    {dx= 0, dy=-1, dz= 0, shade=FACE_SHADE.ny, verts={{0,0,1},{0,0,0},{1,0,0},{1,0,1}}},
    {dx= 0, dy= 0, dz= 1, shade=FACE_SHADE.pz, verts={{1,0,1},{0,0,1},{0,1,1},{1,1,1}}},
    {dx= 0, dy= 0, dz=-1, shade=FACE_SHADE.nz, verts={{0,0,0},{1,0,0},{1,1,0},{0,1,0}}},
}

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
    for cz = 0, self.chunkD - 1 do
        for cy = 0, self.chunkH - 1 do
            for cx = 0, self.chunkW - 1 do
                self.chunks[self:chunkKey(cx, cy, cz)] = newChunk(cx, cy, cz)
            end
        end
    end

    self:flushDirty()
    return self
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
    self.chunks[self:chunkKey(cx, cy, cz)].dirty = true

    for i = 1, 6 do
        local o = NEIGHBOR_OFFSETS[i]
        local nx, ny, nz = x + o[1], y + o[2], z + o[3]
        if self.world:inBounds(nx, ny, nz) then
            local ncx, ncy, ncz = self:chunkCoordsOf(nx, ny, nz)
            if ncx ~= cx or ncy ~= cy or ncz ~= cz then
                self.chunks[self:chunkKey(ncx, ncy, ncz)].dirty = true
            end
        end
    end
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

    for z = z0, zMax do
        for y = y0, yMax do
            for x = x0, xMax do
                local id = world:getBlock(x, y, z)
                if id ~= 0 then
                    local col = palette[id] or {1, 0, 1}
                    local r, g, b = col[1], col[2], col[3]
                    local baseX, baseY, baseZ = x - 1, y - 1, z - 1

                    for f = 1, 6 do
                        local face = FACES[f]
                        if world:getBlock(x + face.dx, y + face.dy, z + face.dz) == 0 then
                            local shade = face.shade
                            local sr, sg, sb = r * shade, g * shade, b * shade

                            for v = 1, 4 do
                                local vp = face.verts[v]
                                vCount = vCount + 1
                                verts[vCount] = {
                                    baseX + vp[1], baseY + vp[2], baseZ + vp[3],
                                    sr, sg, sb, 1,
                                }
                            end
                            idxs[iCount + 1] = vIndex + 1
                            idxs[iCount + 2] = vIndex + 2
                            idxs[iCount + 3] = vIndex + 3
                            idxs[iCount + 4] = vIndex + 1
                            idxs[iCount + 5] = vIndex + 3
                            idxs[iCount + 6] = vIndex + 4
                            iCount = iCount + 6
                            vIndex = vIndex + 4
                        end
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
    for _, chunk in pairs(self.chunks) do chunk.dirty = true end
end

function ChunkManager:flushDirty()
    for _, chunk in pairs(self.chunks) do
        if chunk.dirty then
            self:regenerateChunk(chunk)
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
