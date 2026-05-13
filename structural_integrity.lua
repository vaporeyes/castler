-- ABOUTME: BFS-based stability check. After a block is removed, flood-fills from
-- ABOUTME: each surviving neighbor; any connected component that can't reach y=1
-- ABOUTME: is unsupported and gets collapsed (set to air). Returns the collapsed
-- ABOUTME: blocks with their colors so the caller can spawn particles.

local Stability = {}
Stability.__index = Stability

local NEIGHBORS = {
    { 1, 0, 0}, {-1, 0, 0},
    { 0, 1, 0}, { 0,-1, 0},
    { 0, 0, 1}, { 0, 0,-1},
}

function Stability.new(world)
    local self = setmetatable({}, Stability)
    self.world = world
    -- Pre-allocated queue (flat x,y,z triples) and component buffer (x,y,z,id).
    -- Reused across calls to avoid GC churn during cascades.
    self.queue = {}
    self.component = {}
    return self
end

-- Returns a flat list { x1,y1,z1,id1, x2,y2,z2,id2, ... } of blocks that fell.
function Stability:checkStability(rx, ry, rz)
    local world = self.world
    local palette = world.PALETTE
    local visited = {}
    local collapsed = {}
    local queue = self.queue
    local component = self.component

    for n = 1, 6 do
        local nb = NEIGHBORS[n]
        local sx, sy, sz = rx + nb[1], ry + nb[2], rz + nb[3]
        if world:inBounds(sx, sy, sz) and world:getBlock(sx, sy, sz) ~= 0 then
            local startKey = world:getIndex(sx, sy, sz)
            if not visited[startKey] then
                -- BFS from this neighbor, accumulating its connected component.
                visited[startKey] = true
                queue[1], queue[2], queue[3] = sx, sy, sz
                local head = 1
                local tail = 4

                -- Reset component buffer (truncate, don't realloc).
                local compCount = 0
                compCount = compCount + 1; component[compCount] = sx
                compCount = compCount + 1; component[compCount] = sy
                compCount = compCount + 1; component[compCount] = sz

                local reachedFloor = (sy == 1)

                while head < tail do
                    local cx = queue[head]
                    local cy = queue[head + 1]
                    local cz = queue[head + 2]
                    head = head + 3

                    for k = 1, 6 do
                        local off = NEIGHBORS[k]
                        local nx = cx + off[1]
                        local ny = cy + off[2]
                        local nz = cz + off[3]
                        if world:inBounds(nx, ny, nz) and world:getBlock(nx, ny, nz) ~= 0 then
                            local key = world:getIndex(nx, ny, nz)
                            if not visited[key] then
                                visited[key] = true
                                queue[tail]     = nx
                                queue[tail + 1] = ny
                                queue[tail + 2] = nz
                                tail = tail + 3
                                compCount = compCount + 1; component[compCount] = nx
                                compCount = compCount + 1; component[compCount] = ny
                                compCount = compCount + 1; component[compCount] = nz
                                if ny == 1 then reachedFloor = true end
                            end
                        end
                    end
                end

                if not reachedFloor then
                    for i = 1, compCount, 3 do
                        local cx = component[i]
                        local cy = component[i + 1]
                        local cz = component[i + 2]
                        local id = world:getBlock(cx, cy, cz)
                        local col = palette[id] or {1, 1, 1}
                        world:setBlock(cx, cy, cz, 0)
                        collapsed[#collapsed + 1] = cx
                        collapsed[#collapsed + 1] = cy
                        collapsed[#collapsed + 1] = cz
                        collapsed[#collapsed + 1] = col
                    end
                end
            end
        end
    end

    return collapsed
end

return Stability
