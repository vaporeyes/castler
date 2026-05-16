-- ABOUTME: Top-down 2D minimap. Bakes the topmost-solid block per column into
-- ABOUTME: an ImageData on a throttled timer (cheap, self-correcting after
-- ABOUTME: edits) and overlays a camera position + facing marker.

local Minimap = {}
Minimap.__index = Minimap

local MAP_PX     = 168    -- on-screen size (square)
local MARGIN     = 14
local AIR_R, AIR_G, AIR_B = 0.09, 0.11, 0.15
-- Rebuild is amortized across frames so it never blocks one. ~8 rows/frame
-- at 60fps sweeps a 128-deep world in ~0.27s with sub-ms per-frame cost.
local ROWS_PER_FRAME = 8

function Minimap.new(world)
    local self = setmetatable({}, Minimap)
    self.world = world
    self.visible = true
    self.scanZ = 1               -- next row to bake
    self.imageData = love.image.newImageData(world.width, world.depth)
    self.image = love.graphics.newImage(self.imageData)
    self.image:setFilter("nearest", "nearest")
    return self
end

function Minimap:toggle()
    self.visible = not self.visible
    return self.visible
end

-- Bake a slice of rows into the ImageData. Reads world.data directly (flat
-- 1D array) and steps the column index by -width per y, avoiding the
-- getBlock method-call + bounds-check overhead in the hot loop.
function Minimap:bakeRows(z0, z1)
    local world = self.world
    local data = world.data
    local palette = world.PALETTE
    local w, h = world.width, world.height
    local img = self.imageData
    local invH = 1 / h

    for z = z0, z1 do
        -- Index of (x=1, y=h, z) then walk x outward, y downward.
        local rowBase = ((z - 1) * h + (h - 1)) * w
        for x = 1, w do
            local idx = rowBase + x
            local topId, topY = 0, 0
            for y = h, 1, -1 do
                local id = data[idx]
                if id ~= 0 then topId, topY = id, y; break end
                idx = idx - w
            end
            local r, g, b
            if topId == 0 then
                r, g, b = AIR_R, AIR_G, AIR_B
            else
                local col = palette[topId] or {1, 0, 1}
                local shade = 0.45 + 0.55 * (topY * invH)
                r = math.min(1, col[1] * shade)
                g = math.min(1, col[2] * shade)
                b = math.min(1, col[3] * shade)
            end
            img:setPixel(x - 1, z - 1, r, g, b, 1)
        end
    end
end

function Minimap:update(_)
    if not self.visible then return end
    local d = self.world.depth
    local z0 = self.scanZ
    local z1 = math.min(d, z0 + ROWS_PER_FRAME - 1)
    self:bakeRows(z0, z1)
    self.image:replacePixels(self.imageData)
    self.scanZ = (z1 >= d) and 1 or (z1 + 1)
end

-- camX, camZ: world-space focus position. dirX, dirZ: horizontal facing.
function Minimap:draw(camX, camZ, dirX, dirZ)
    if not self.visible then return end

    local world = self.world
    local sw, sh = love.graphics.getDimensions()
    local x0 = sw - MAP_PX - MARGIN
    local y0 = sh - MAP_PX - MARGIN
    local sx = MAP_PX / world.width
    local sy = MAP_PX / world.depth

    love.graphics.push("all")
    love.graphics.setDepthMode()

    -- Backing + frame.
    love.graphics.setColor(0, 0, 0, 0.45)
    love.graphics.rectangle("fill", x0 - 3, y0 - 3, MAP_PX + 6, MAP_PX + 6, 4, 4)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.image, x0, y0, 0, sx, sy)
    love.graphics.setColor(0.40, 0.55, 0.70, 0.9)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x0 - 3, y0 - 3, MAP_PX + 6, MAP_PX + 6, 4, 4)

    -- Camera marker: world x -> right, world z -> down (matches image rows).
    local mx = x0 + ((camX - 1) / world.width) * MAP_PX
    local my = y0 + ((camZ - 1) / world.depth) * MAP_PX
    mx = math.max(x0, math.min(x0 + MAP_PX, mx))
    my = math.max(y0, math.min(y0 + MAP_PX, my))

    local len = math.sqrt((dirX or 0)^2 + (dirZ or 0)^2)
    if len > 1e-4 then
        local fx, fz = dirX / len, dirZ / len
        love.graphics.setColor(1, 0.9, 0.3, 0.95)
        love.graphics.setLineWidth(2)
        love.graphics.line(mx, my, mx + fx * 14, my + fz * 14)
    end
    love.graphics.setColor(1, 0.9, 0.3, 1)
    love.graphics.circle("fill", mx, my, 3)
    love.graphics.setColor(0, 0, 0, 0.8)
    love.graphics.circle("line", mx, my, 3)

    love.graphics.pop()
end

return Minimap
