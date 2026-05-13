-- ABOUTME: Mouse-driven build/destroy. Unprojects the cursor, runs a 3D DDA
-- ABOUTME: voxel traversal, renders a wireframe ghost cube, and mutates the world.
-- ABOUTME: Supports brush, line, and rectangle tools with a two-click commit pattern.

local Matrix = require("matrix")

local BuildManager = {}
BuildManager.__index = BuildManager

-- World units; ray distance cap. Needs to exceed (camera distance + world diagonal)
-- so the RTS camera can target blocks anywhere on the map at any zoom level.
local MAX_REACH = 800

-- Unit cube edges (pairs of corner indices). Corners are indexed 0..7 by their
-- bit pattern: bit0 = +x, bit1 = +y, bit2 = +z.
local CUBE_CORNERS = {
    {0,0,0}, {1,0,0}, {0,1,0}, {1,1,0},
    {0,0,1}, {1,0,1}, {0,1,1}, {1,1,1},
}
local CUBE_EDGES = {
    {1,2}, {3,4}, {5,6}, {7,8},  -- along X
    {1,3}, {2,4}, {5,7}, {6,8},  -- along Y
    {1,5}, {2,6}, {3,7}, {4,8},  -- along Z
}

local TOOL_BRUSH  = "brush"
local TOOL_LINE   = "line"
local TOOL_RECT   = "rect"
local TOOL_BOX    = "box"
local TOOL_SPHERE = "sphere"

function BuildManager.new(world, renderer, camera, stability, particles)
    local self = setmetatable({}, BuildManager)
    self.world = world
    self.renderer = renderer
    self.camera = camera
    self.stability = stability
    self.particles = particles
    self.activeBlockId = 1
    self.hit = nil          -- {x, y, z, nx, ny, nz}
    self.tool = TOOL_BRUSH
    self.pending = nil      -- {x, y, z, axis, mode}
    -- Manual Y offset applied to the second-click end point. Lets the user
    -- build vertical extent for box/sphere/line ops when there's nothing
    -- above the floor to point at. Reset whenever an op completes/cancels.
    self.heightOffset = 0
    self._heightAccum = 0
    return self
end

function BuildManager:setActiveBlock(id) self.activeBlockId = id end

function BuildManager:setTool(tool)
    if tool ~= self.tool then
        self.tool = tool
        self.pending = nil
        self.heightOffset = 0
        self._heightAccum = 0
    end
end

function BuildManager:cancelPending()
    if self.pending then
        self.pending = nil
        self.heightOffset = 0
        self._heightAccum = 0
        return true
    end
    return false
end

local function toolUsesHeightOffset(tool)
    return tool == TOOL_BOX or tool == TOOL_SPHERE or tool == TOOL_LINE
end

function BuildManager:nudgeHeight(delta)
    if not self.pending or not toolUsesHeightOffset(self.tool) then return end
    self.heightOffset = self.heightOffset + delta
end

local function unprojectRay(camera, mouseX, mouseY, screenW, screenH)
    local view = camera:viewMatrix()
    local proj = camera:projectionMatrix(screenW / screenH)
    local vp = Matrix.mul(proj, view)
    local invVP = Matrix.inverse(vp)
    if not invVP then return nil end

    local nx = 2 * mouseX / screenW - 1
    local ny = 1 - 2 * mouseY / screenH

    local function unp(z)
        local x, y, zz, w = Matrix.mulVec4(invVP, nx, ny, z, 1)
        if math.abs(w) < 1e-9 then return nil end
        return {x / w, y / w, zz / w}
    end

    local near = unp(-1)
    local far  = unp( 1)
    if not (near and far) then return nil end

    local dx = far[1] - near[1]
    local dy = far[2] - near[2]
    local dz = far[3] - near[3]
    local len = math.sqrt(dx*dx + dy*dy + dz*dz)
    if len < 1e-9 then return nil end
    return near, {dx/len, dy/len, dz/len}
end

local function dda(world, origin, dir, maxDist)
    local ox, oy, oz = origin[1], origin[2], origin[3]
    local dx, dy, dz = dir[1],    dir[2],    dir[3]

    local cx = math.floor(ox)
    local cy = math.floor(oy)
    local cz = math.floor(oz)

    local stepX = (dx > 0) and 1 or ((dx < 0) and -1 or 0)
    local stepY = (dy > 0) and 1 or ((dy < 0) and -1 or 0)
    local stepZ = (dz > 0) and 1 or ((dz < 0) and -1 or 0)

    local function nextBoundary(o, c, step)
        if step > 0 then return (c + 1 - o)
        elseif step < 0 then return (c - o)
        else return math.huge end
    end

    local tMaxX = (stepX ~= 0) and (nextBoundary(ox, cx, stepX) / dx) or math.huge
    local tMaxY = (stepY ~= 0) and (nextBoundary(oy, cy, stepY) / dy) or math.huge
    local tMaxZ = (stepZ ~= 0) and (nextBoundary(oz, cz, stepZ) / dz) or math.huge

    local tDeltaX = (stepX ~= 0) and math.abs(1 / dx) or math.huge
    local tDeltaY = (stepY ~= 0) and math.abs(1 / dy) or math.huge
    local tDeltaZ = (stepZ ~= 0) and math.abs(1 / dz) or math.huge

    local nx, ny, nz = 0, 0, 0
    local t = 0

    local maxBoundX = world.width
    local maxBoundY = world.height
    local maxBoundZ = world.depth

    while t <= maxDist do
        local bx, by, bz = cx + 1, cy + 1, cz + 1
        if world:inBounds(bx, by, bz) then
            local id = world:getBlock(bx, by, bz)
            if id ~= 0 then
                return {x = bx, y = by, z = bz, nx = nx, ny = ny, nz = nz, t = t, id = id}
            end
        end

        if tMaxX < tMaxY and tMaxX < tMaxZ then
            cx = cx + stepX
            t = tMaxX
            tMaxX = tMaxX + tDeltaX
            nx, ny, nz = -stepX, 0, 0
        elseif tMaxY < tMaxZ then
            cy = cy + stepY
            t = tMaxY
            tMaxY = tMaxY + tDeltaY
            nx, ny, nz = 0, -stepY, 0
        else
            cz = cz + stepZ
            t = tMaxZ
            tMaxZ = tMaxZ + tDeltaZ
            nx, ny, nz = 0, 0, -stepZ
        end

        if (stepX > 0 and cx >= maxBoundX) or (stepX < 0 and cx < 0)
        or (stepY > 0 and cy >= maxBoundY) or (stepY < 0 and cy < 0)
        or (stepZ > 0 and cz >= maxBoundZ) or (stepZ < 0 and cz < 0) then
            return nil
        end
    end
    return nil
end

function BuildManager:update(dt)
    -- Smooth hold-to-repeat for height adjustment while an op is pending.
    if self.pending and toolUsesHeightOffset(self.tool) and love.keyboard then
        local rate = 10  -- cells per second
        local accumDelta = 0
        if love.keyboard.isDown("up")   or love.keyboard.isDown("pageup")   then accumDelta = accumDelta + 1 end
        if love.keyboard.isDown("down") or love.keyboard.isDown("pagedown") then accumDelta = accumDelta - 1 end
        if accumDelta ~= 0 then
            self._heightAccum = self._heightAccum + accumDelta * rate * (dt or 0)
            while self._heightAccum >= 1 do
                self.heightOffset = self.heightOffset + 1
                self._heightAccum = self._heightAccum - 1
            end
            while self._heightAccum <= -1 do
                self.heightOffset = self.heightOffset - 1
                self._heightAccum = self._heightAccum + 1
            end
        else
            self._heightAccum = 0
        end
    end

    if not love.mouse then self.hit = nil; return end
    local sw, sh = love.graphics.getDimensions()
    local mx, my
    -- When the OS cursor is hidden (fly mode), aim from the screen center so
    -- the ghost cube sits where the user is looking instead of at a stale
    -- cursor position the user can't see.
    if love.mouse.getRelativeMode and love.mouse.getRelativeMode() then
        mx, my = sw * 0.5, sh * 0.5
    else
        mx, my = love.mouse.getPosition()
    end
    local origin, dir = unprojectRay(self.camera, mx, my, sw, sh)
    if not origin then self.hit = nil; return end
    self.hit = dda(self.world, origin, dir, MAX_REACH)
end

local function projectPoint(mvp, sw, sh, x, y, z)
    local cx, cy, cz, cw = Matrix.mulVec4(mvp, x, y, z, 1)
    if cw <= 0 then return nil end
    local nx = cx / cw
    local ny = cy / cw
    return (nx * 0.5 + 0.5) * sw, (1 - (ny * 0.5 + 0.5)) * sh, true
end

local function shiftHeld()
    return love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")
end

local function axisLockHeld()
    -- Ctrl on win/linux, Cmd on macOS; either is treated as "snap to dominant axis".
    return love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")
        or love.keyboard.isDown("lgui")  or love.keyboard.isDown("rgui")
end

-- Collapse the smaller deltas so only the largest survives. Used by the line
-- tool when axis-lock is held: result is colinear with the anchor along one axis.
local function snapLineAxis(sx, sy, sz, ex, ey, ez)
    local dx = math.abs(ex - sx)
    local dy = math.abs(ey - sy)
    local dz = math.abs(ez - sz)
    if dx >= dy and dx >= dz then return ex, sy, sz
    elseif dy >= dz then return sx, ey, sz
    else return sx, sy, ez end
end

-- For rect tool: keep the fixed axis from the start point, then collapse the
-- smaller of the two free deltas so the rect is 1 wide along that axis.
local function snapRectAxis(sx, sy, sz, ex, ey, ez, axis)
    if axis == "y" then
        if math.abs(ex - sx) >= math.abs(ez - sz) then return ex, sy, sz
        else return sx, sy, ez end
    elseif axis == "x" then
        if math.abs(ey - sy) >= math.abs(ez - sz) then return sx, ey, sz
        else return sx, sy, ez end
    else  -- z plane
        if math.abs(ex - sx) >= math.abs(ey - sy) then return ex, sy, sz
        else return sx, ey, sz end
    end
end

-- Cell currently under the cursor for the active mode (place vs remove).
function BuildManager:cursorCell()
    if not self.hit then return nil end
    local h = self.hit
    if shiftHeld() then
        return h.x, h.y, h.z, "remove", h.nx, h.ny, h.nz
    else
        return h.x + h.nx, h.y + h.ny, h.z + h.nz, "place", h.nx, h.ny, h.nz
    end
end

local function normalToAxis(nx, ny, nz)
    if math.abs(ny) > 0 then return "y"
    elseif math.abs(nx) > 0 then return "x"
    else return "z" end
end

-- Inclusive integer line via supercover-ish step. Steps along the dominant
-- axis count, rounding the other two. Good enough for axis-aligned and gentle
-- diagonals; users get a clean staircase rather than missed cells.
local function collectLine(x1, y1, z1, x2, y2, z2, out)
    local n = math.max(math.abs(x2 - x1), math.abs(y2 - y1), math.abs(z2 - z1))
    if n == 0 then
        out[#out + 1] = x1; out[#out + 1] = y1; out[#out + 1] = z1
        return
    end
    local lastX, lastY, lastZ
    for i = 0, n do
        local t = i / n
        local x = math.floor(x1 + (x2 - x1) * t + 0.5)
        local y = math.floor(y1 + (y2 - y1) * t + 0.5)
        local z = math.floor(z1 + (z2 - z1) * t + 0.5)
        if x ~= lastX or y ~= lastY or z ~= lastZ then
            out[#out + 1] = x; out[#out + 1] = y; out[#out + 1] = z
            lastX, lastY, lastZ = x, y, z
        end
    end
end

-- Solid 3D box between two opposite corners (inclusive on all six faces).
local function collectBox(x1, y1, z1, x2, y2, z2, out)
    local xLo, xHi = math.min(x1, x2), math.max(x1, x2)
    local yLo, yHi = math.min(y1, y2), math.max(y1, y2)
    local zLo, zHi = math.min(z1, z2), math.max(z1, z2)
    for x = xLo, xHi do
        for y = yLo, yHi do
            for z = zLo, zHi do
                out[#out + 1] = x; out[#out + 1] = y; out[#out + 1] = z
            end
        end
    end
end

-- Solid sphere centered on (cx, cy, cz). Radius is the integer distance to the
-- second-click cell, so a single click after the anchor produces a near-1 ball
-- and dragging outward grows it predictably.
local function collectSphere(cx, cy, cz, radius, out)
    if radius < 1 then radius = 1 end
    local r2 = radius * radius
    local iR = math.ceil(radius)
    for dz = -iR, iR do
        local z = cz + dz
        for dy = -iR, iR do
            local y = cy + dy
            for dx = -iR, iR do
                if dx*dx + dy*dy + dz*dz <= r2 then
                    out[#out + 1] = cx + dx
                    out[#out + 1] = y
                    out[#out + 1] = z
                end
            end
        end
    end
end

-- Rect lies on the plane perpendicular to `axis`. The fixed coord is taken
-- from the start point; the other two are taken from min..max of start/end.
local function collectRect(x1, y1, z1, x2, y2, z2, axis, out)
    local xLo, xHi = math.min(x1, x2), math.max(x1, x2)
    local yLo, yHi = math.min(y1, y2), math.max(y1, y2)
    local zLo, zHi = math.min(z1, z2), math.max(z1, z2)
    if axis == "y" then yLo, yHi = y1, y1
    elseif axis == "x" then xLo, xHi = x1, x1
    elseif axis == "z" then zLo, zHi = z1, z1
    end
    for x = xLo, xHi do
        for y = yLo, yHi do
            for z = zLo, zHi do
                out[#out + 1] = x; out[#out + 1] = y; out[#out + 1] = z
            end
        end
    end
end

-- Returns the list of cells (flat {x,y,z,x,y,z,...}) the current operation
-- would affect, given an end-point cell. Caller already chose place vs remove.
function BuildManager:cellsForOperation(endX, endY, endZ, axis)
    local cells = {}
    if self.tool == TOOL_BRUSH or not self.pending then
        cells[1] = endX; cells[2] = endY; cells[3] = endZ
        return cells
    end
    local p = self.pending
    local locked = axisLockHeld()
    -- Apply the manual Y offset to the end point for tools that support it.
    -- Lets the user dial in vertical extent for box/sphere/line ops when the
    -- raycast can only target floor tiles.
    if toolUsesHeightOffset(self.tool) then
        endY = endY + self.heightOffset
    end

    if self.tool == TOOL_LINE then
        if locked then
            endX, endY, endZ = snapLineAxis(p.x, p.y, p.z, endX, endY, endZ)
        end
        collectLine(p.x, p.y, p.z, endX, endY, endZ, cells)
    elseif self.tool == TOOL_RECT then
        local planeAxis = p.axis or axis or "y"
        if locked then
            endX, endY, endZ = snapRectAxis(p.x, p.y, p.z, endX, endY, endZ, planeAxis)
        end
        collectRect(p.x, p.y, p.z, endX, endY, endZ, planeAxis, cells)
    elseif self.tool == TOOL_BOX then
        collectBox(p.x, p.y, p.z, endX, endY, endZ, cells)
    elseif self.tool == TOOL_SPHERE then
        local dx, dy, dz = endX - p.x, endY - p.y, endZ - p.z
        local r = math.floor(math.sqrt(dx*dx + dy*dy + dz*dz) + 0.5)
        collectSphere(p.x, p.y, p.z, r, cells)
    end
    return cells
end

function BuildManager:applyCells(cells, mode)
    if #cells == 0 then return false end
    local world = self.world
    local changed = false
    local id = self.activeBlockId
    local renderer = self.renderer
    if mode == "remove" then
        for i = 1, #cells, 3 do
            local x, y, z = cells[i], cells[i+1], cells[i+2]
            if y > 1 and world:inBounds(x, y, z) then
                local existing = world:getBlock(x, y, z)
                if existing ~= 0 then
                    local col = world.PALETTE[existing] or {1,1,1}
                    world:setBlock(x, y, z, 0)
                    renderer:markDirty(x, y, z)
                    self.particles:spawnBlock(x, y, z, col)
                    changed = true
                end
            end
        end
        if changed then
            for i = 1, #cells, 3 do
                local x, y, z = cells[i], cells[i+1], cells[i+2]
                local collapsed = self.stability:checkStability(x, y, z)
                for j = 1, #collapsed, 4 do
                    local cx, cy, cz = collapsed[j], collapsed[j+1], collapsed[j+2]
                    renderer:markDirty(cx, cy, cz)
                    self.particles:spawnBlock(cx, cy, cz, collapsed[j+3])
                end
            end
        end
    else
        for i = 1, #cells, 3 do
            local x, y, z = cells[i], cells[i+1], cells[i+2]
            if world:inBounds(x, y, z) and world:getBlock(x, y, z) == 0 then
                if world:setBlock(x, y, z, id) then
                    renderer:markDirty(x, y, z)
                    changed = true
                end
            end
        end
    end
    if changed then renderer:flushDirty() end
    return changed
end

local function drawGhostCube(mvp, sw, sh, cellX, cellY, cellZ, colorR, colorG, colorB)
    local inset = 0.02
    local x0 = (cellX - 1) + inset; local x1 = cellX - inset
    local y0 = (cellY - 1) + inset; local y1 = cellY - inset
    local z0 = (cellZ - 1) + inset; local z1 = cellZ - inset

    local screen = {}
    for i = 1, 8 do
        local c = CUBE_CORNERS[i]
        local x = (c[1] == 0) and x0 or x1
        local y = (c[2] == 0) and y0 or y1
        local z = (c[3] == 0) and z0 or z1
        local sx, sy, vis = projectPoint(mvp, sw, sh, x, y, z)
        screen[i] = vis and {sx, sy} or nil
    end

    love.graphics.setColor(colorR, colorG, colorB, 1)
    for _, e in ipairs(CUBE_EDGES) do
        local a = screen[e[1]]
        local b = screen[e[2]]
        if a and b then
            love.graphics.line(a[1], a[2], b[1], b[2])
        end
    end
end

function BuildManager:draw()
    if not self.hit and not self.pending then return end

    local sw, sh = love.graphics.getDimensions()
    local view = self.camera:viewMatrix()
    local proj = self.camera:projectionMatrix(sw / sh)
    local mvp = Matrix.mul(proj, view)

    -- Determine end-point and color.
    local endX, endY, endZ, mode, nx, ny, nz = self:cursorCell()
    local colorR, colorG, colorB

    -- If we have a pending start but no cursor over a block, anchor the preview
    -- to the start cell so the user still sees the in-progress operation.
    if not endX and self.pending then
        endX, endY, endZ = self.pending.x, self.pending.y, self.pending.z
        mode = self.pending.mode
    end

    if not endX then return end

    if mode == "remove" then
        colorR, colorG, colorB = 1, 0.3, 0.3
    else
        colorR, colorG, colorB = 0.3, 1, 0.4
    end

    local cells = self:cellsForOperation(endX, endY, endZ, nx and normalToAxis(nx, ny, nz) or nil)

    -- Sphere/box previews can be thousands of cells. To keep the wireframe
    -- pass cheap, when the result is large we render only "shell" cells -
    -- cells that are missing at least one neighbor inside the set. The result
    -- is visually identical (the interior cubes would have been hidden behind
    -- the outer ones anyway) at a fraction of the line-draw cost.
    local PREVIEW_FULL_CAP = 500
    local total = #cells / 3
    local previewCells = cells
    if total > PREVIEW_FULL_CAP then
        local present = {}
        for i = 1, #cells, 3 do
            present[cells[i] .. "," .. cells[i+1] .. "," .. cells[i+2]] = true
        end
        previewCells = {}
        for i = 1, #cells, 3 do
            local x, y, z = cells[i], cells[i+1], cells[i+2]
            if not (present[(x+1)..","..y..","..z]
                and present[(x-1)..","..y..","..z]
                and present[x..","..(y+1)..","..z]
                and present[x..","..(y-1)..","..z]
                and present[x..","..y..","..(z+1)]
                and present[x..","..y..","..(z-1)]) then
                previewCells[#previewCells+1] = x
                previewCells[#previewCells+1] = y
                previewCells[#previewCells+1] = z
            end
        end
    end

    love.graphics.push("all")
    love.graphics.setDepthMode()
    love.graphics.setLineWidth(2)
    for i = 1, #previewCells, 3 do
        drawGhostCube(mvp, sw, sh, previewCells[i], previewCells[i+1], previewCells[i+2], colorR, colorG, colorB)
    end

    -- Highlight the pending start point with a thicker outline so the anchor is obvious.
    if self.pending then
        love.graphics.setLineWidth(3.5)
        love.graphics.setColor(1, 0.85, 0.25, 1)
        drawGhostCube(mvp, sw, sh, self.pending.x, self.pending.y, self.pending.z, 1, 0.85, 0.25)
    end
    love.graphics.pop()
end

function BuildManager:mousepressed(_, _, button)
    if button ~= 1 or not self.hit then return end
    local x, y, z, mode, nx, ny, nz = self:cursorCell()
    if not x then return end

    if self.tool == TOOL_BRUSH then
        local cells = { x, y, z }
        self:applyCells(cells, mode)
        return
    end

    -- Two-click flow for line / rect.
    if not self.pending then
        self.pending = {
            x = x, y = y, z = z,
            mode = mode,
            axis = normalToAxis(nx, ny, nz),
        }
        return
    end

    -- Second click: commit using the pending mode (sticky from first click —
    -- avoids accidentally mixing place and remove mid-operation if Shift slips).
    local p = self.pending
    local cells = self:cellsForOperation(x, y, z, p.axis)
    self:applyCells(cells, p.mode)
    self.pending = nil
    self.heightOffset = 0
    self._heightAccum = 0
end

BuildManager.TOOLS = {
    brush = TOOL_BRUSH,
    line  = TOOL_LINE,
    rect  = TOOL_RECT,
}

return BuildManager
