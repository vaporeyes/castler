-- ABOUTME: Voxel data manager. Stores the 3D block grid in a flat 1D table
-- ABOUTME: for cache locality. 0 = Air, any positive integer = Block ID.

local VoxelWorld = {}
VoxelWorld.__index = VoxelWorld

-- User-placeable block metadata. Imported materials can still extend PALETTE
-- directly without becoming hotbar entries.
VoxelWorld.BLOCKS = {
    [1] = {name = "Stone", color = {0.55, 0.55, 0.58}, placeable = true},
    [2] = {name = "Wood",  color = {0.60, 0.40, 0.22}, placeable = true},
    [3] = {name = "Dirt",  color = {0.45, 0.30, 0.15}, placeable = true},
    [4] = {name = "Grass", color = {0.35, 0.70, 0.30}, placeable = true},
    [5] = {name = "Sand",  color = {0.85, 0.80, 0.60}, placeable = true},
}

-- Block ID -> RGB color lookup. Index 0 is Air (no color).
VoxelWorld.PALETTE = {}
for id, meta in pairs(VoxelWorld.BLOCKS) do
    VoxelWorld.PALETTE[id] = meta.color
end

function VoxelWorld.new(width, height, depth)
    local self = setmetatable({}, VoxelWorld)
    self.width = width
    self.height = height
    self.depth = depth
    self.size = width * height * depth

    -- Pre-allocate flat 1D table; all Air to start.
    local data = {}
    for i = 1, self.size do
        data[i] = 0
    end
    self.data = data

    -- Floor layer at y=1 (Lua 1-based indexing): fill with Grass (id 4).
    for x = 1, width do
        for z = 1, depth do
            self:setBlock(x, 1, z, 4)
        end
    end

    return self
end

-- Map (x, y, z) -> 1D index. x is fastest-varying (best cache locality
-- when iterating in (y, z, x) order, which mesh generation will do).
function VoxelWorld:getIndex(x, y, z)
    return ((z - 1) * self.height + (y - 1)) * self.width + x
end

function VoxelWorld:getXYZ(index)
    local i = index - 1
    local x = (i % self.width) + 1
    local rest = math.floor(i / self.width)
    local y = (rest % self.height) + 1
    local z = math.floor(rest / self.height) + 1
    return x, y, z
end

function VoxelWorld:inBounds(x, y, z)
    return x >= 1 and x <= self.width
       and y >= 1 and y <= self.height
       and z >= 1 and z <= self.depth
end

function VoxelWorld:getBlock(x, y, z)
    if not self:inBounds(x, y, z) then
        return 0
    end
    return self.data[self:getIndex(x, y, z)]
end

function VoxelWorld:setBlock(x, y, z, id)
    if not self:inBounds(x, y, z) then
        return false
    end
    self.data[self:getIndex(x, y, z)] = id
    return true
end

function VoxelWorld:blockName(id)
    local meta = self.BLOCKS[id]
    return meta and meta.name or ("#" .. tostring(id))
end

function VoxelWorld:isPlaceableBlock(id)
    local meta = self.BLOCKS[id]
    return meta and meta.placeable == true
end

function VoxelWorld:placeableBlockIds()
    local ids = {}
    for id, meta in pairs(self.BLOCKS) do
        if meta.placeable and self.PALETTE[id] then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    return ids
end

-- Reset every cell to air. Faster than looping setBlock since we skip the
-- bounds check on every write.
function VoxelWorld:clear()
    local data = self.data
    for i = 1, self.size do data[i] = 0 end
end

-- Bulk iterator. Callback receives (x, y, z, id) for every solid block
-- (id != 0). Traversal order is x-fastest for cache-friendly reads.
function VoxelWorld:forEachSolid(callback)
    local data = self.data
    local w, h, d = self.width, self.height, self.depth
    local idx = 0
    for z = 1, d do
        for y = 1, h do
            for x = 1, w do
                idx = idx + 1
                local id = data[idx]
                if id ~= 0 then
                    callback(x, y, z, id)
                end
            end
        end
    end
end

return VoxelWorld
