-- ABOUTME: BFS-based stability check. After a block is removed, flood-fills from
-- ABOUTME: each surviving neighbor; any connected component that can't reach y=1
-- ABOUTME: is unsupported and gets collapsed (set to air), either immediately
-- ABOUTME: or across multiple update frames from a small dirty queue.

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
    self.pending = {}
    self.pendingHead = 1
    self.current = nil
    self.asyncQueue = {}
    self.asyncComponent = {}
    return self
end

function Stability:enqueueCheck(rx, ry, rz, undoOp)
    local pending = self.pending
    pending[#pending + 1] = rx
    pending[#pending + 1] = ry
    pending[#pending + 1] = rz
    pending[#pending + 1] = undoOp or false
end

function Stability:hasPending()
    return self.current ~= nil or self.pendingHead <= #self.pending
end

local function startNextCheck(self)
    local pending = self.pending
    local head = self.pendingHead
    if head > #pending then
        self.pending = {}
        self.pendingHead = 1
        return false
    end
    self.current = {
        rx = pending[head],
        ry = pending[head + 1],
        rz = pending[head + 2],
        undoOp = pending[head + 3],
        neighbor = 1,
        visited = {},
        phase = "seed",
    }
    self.pendingHead = head + 4
    return true
end

local function startNextComponent(self, state)
    local world = self.world
    while state.neighbor <= 6 do
        local nb = NEIGHBORS[state.neighbor]
        state.neighbor = state.neighbor + 1
        local sx, sy, sz = state.rx + nb[1], state.ry + nb[2], state.rz + nb[3]
        if world:inBounds(sx, sy, sz) and world:getBlock(sx, sy, sz) ~= 0 then
            local startKey = world:getIndex(sx, sy, sz)
            if not state.visited[startKey] then
                local queue = self.asyncQueue
                local component = self.asyncComponent
                state.visited[startKey] = true
                queue[1], queue[2], queue[3] = sx, sy, sz
                state.head = 1
                state.tail = 4
                component[1], component[2], component[3] = sx, sy, sz
                state.compCount = 3
                state.reachedFloor = (sy == 1)
                state.phase = "bfs"
                return true
            end
        end
    end
    return false
end

local function clearAsyncBuffers(self, state)
    local queue = self.asyncQueue
    local component = self.asyncComponent
    for i = 1, state.tail or 0 do queue[i] = nil end
    for i = 1, state.compCount or 0 do component[i] = nil end
end

function Stability:update(maxSeconds, onCollapse)
    if not love or not love.timer then return 0 end
    local deadline = love.timer.getTime() + (maxSeconds or 0.002)
    local world = self.world
    local collapsed = 0

    while love.timer.getTime() < deadline do
        local state = self.current
        if not state then
            if not startNextCheck(self) then break end
            state = self.current
        end

        if state.phase == "seed" then
            if not startNextComponent(self, state) then
                self.current = nil
            end
        elseif state.phase == "bfs" then
            if state.head < state.tail then
                local queue = self.asyncQueue
                local component = self.asyncComponent
                local cx = queue[state.head]
                local cy = queue[state.head + 1]
                local cz = queue[state.head + 2]
                state.head = state.head + 3

                for k = 1, 6 do
                    local off = NEIGHBORS[k]
                    local nx = cx + off[1]
                    local ny = cy + off[2]
                    local nz = cz + off[3]
                    if world:inBounds(nx, ny, nz) and world:getBlock(nx, ny, nz) ~= 0 then
                        local key = world:getIndex(nx, ny, nz)
                        if not state.visited[key] then
                            state.visited[key] = true
                            queue[state.tail]     = nx
                            queue[state.tail + 1] = ny
                            queue[state.tail + 2] = nz
                            state.tail = state.tail + 3
                            state.compCount = state.compCount + 1; component[state.compCount] = nx
                            state.compCount = state.compCount + 1; component[state.compCount] = ny
                            state.compCount = state.compCount + 1; component[state.compCount] = nz
                            if ny == 1 then state.reachedFloor = true end
                        end
                    end
                end
            elseif state.reachedFloor then
                clearAsyncBuffers(self, state)
                state.phase = "seed"
            else
                state.phase = "collapse"
                state.collapseAt = 1
            end
        elseif state.phase == "collapse" then
            local component = self.asyncComponent
            if state.collapseAt <= state.compCount then
                local cx = component[state.collapseAt]
                local cy = component[state.collapseAt + 1]
                local cz = component[state.collapseAt + 2]
                state.collapseAt = state.collapseAt + 3
                local id = world:getBlock(cx, cy, cz)
                if id ~= 0 then
                    world:setBlock(cx, cy, cz, 0)
                    collapsed = collapsed + 1
                    if onCollapse then onCollapse(cx, cy, cz, id, state.undoOp) end
                end
            else
                clearAsyncBuffers(self, state)
                state.phase = "seed"
            end
        end
    end

    return collapsed
end

-- Returns a flat list { x,y,z,id, x,y,z,id, ... } of blocks that fell. The
-- `id` is the BLOCK ID before collapse so callers can record undo state and
-- look up the particle color from the palette themselves.
function Stability:checkStability(rx, ry, rz)
    local world = self.world
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
                        world:setBlock(cx, cy, cz, 0)
                        collapsed[#collapsed + 1] = cx
                        collapsed[#collapsed + 1] = cy
                        collapsed[#collapsed + 1] = cz
                        collapsed[#collapsed + 1] = id
                    end
                end
            end
        end
    end

    return collapsed
end

return Stability
