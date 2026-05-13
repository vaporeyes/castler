-- ABOUTME: 2D HUD overlay - hotbar/palette, status line, control hints. Drawn
-- ABOUTME: with depth testing disabled so it sits on top of the 3D scene.

local UI = {}
UI.__index = UI

local SLOT_SIZE = 48
local SLOT_GAP  = 6
local BLOCK_NAMES = {
    [1] = "Stone",
    [2] = "Wood",
    [3] = "Dirt",
    [4] = "Grass",
    [5] = "Sand",
}

local TOOL_LABELS = {
    brush = "Brush",
    line  = "Line",
    rect  = "Rect",
}

function UI.new(world, builder, renderer, grid)
    local self = setmetatable({}, UI)
    self.world = world
    self.builder = builder
    self.renderer = renderer
    self.grid = grid
    return self
end

local function drawSlot(x, y, color, active, label)
    -- Slot backdrop
    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.rectangle("fill", x, y, SLOT_SIZE, SLOT_SIZE, 4, 4)

    -- Color swatch (slightly inset).
    local pad = 6
    love.graphics.setColor(color[1], color[2], color[3], 1)
    love.graphics.rectangle("fill", x + pad, y + pad, SLOT_SIZE - pad*2, SLOT_SIZE - pad*2, 3, 3)

    -- Border: thick white for active, thin gray otherwise.
    if active then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setLineWidth(3)
    else
        love.graphics.setColor(0.4, 0.4, 0.45, 1)
        love.graphics.setLineWidth(1)
    end
    love.graphics.rectangle("line", x, y, SLOT_SIZE, SLOT_SIZE, 4, 4)

    -- Hotkey label
    love.graphics.setColor(1, 1, 1, 0.85)
    love.graphics.print(label, x + 4, y + 2)
end

function UI:draw()
    love.graphics.push("all")
    love.graphics.setDepthMode()

    local sw, sh = love.graphics.getDimensions()
    local palette = self.world.PALETTE

    -- Count slots (palette is sparse-but-dense-1..5).
    local maxId = 0
    for id in pairs(palette) do
        if id > maxId then maxId = id end
    end

    local totalWidth = maxId * SLOT_SIZE + (maxId - 1) * SLOT_GAP
    local startX = (sw - totalWidth) * 0.5
    local y = sh - SLOT_SIZE - 16

    for id = 1, maxId do
        local color = palette[id]
        if color then
            local x = startX + (id - 1) * (SLOT_SIZE + SLOT_GAP)
            drawSlot(x, y, color, id == self.builder.activeBlockId, tostring(id))
        end
    end

    -- Status line above the hotbar: active block + tool.
    local active = self.builder.activeBlockId
    local name = BLOCK_NAMES[active] or ("#" .. active)
    local toolLabel = TOOL_LABELS[self.builder.tool] or self.builder.tool
    local pendingTag = self.builder.pending and "  (anchor set - click end point)" or ""
    local statusY = y - 22
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf(name .. "  -  " .. toolLabel .. pendingTag, 0, statusY, sw, "center")

    -- Top-left: title, FPS, control hints.
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Castler", 10, 10)
    love.graphics.setColor(0.75, 0.78, 0.85, 1)
    love.graphics.print(string.format("FPS %d", love.timer.getFPS()), 10, 28)
    if self.renderer and self.renderer.getStats then
        local v, t, drawn, total = self.renderer:getStats()
        love.graphics.print(
            string.format("Chunks %d/%d   Tris %d", drawn, total, t),
            120, 28)
    end
    love.graphics.print("WASD pan  |  scroll zoom  |  RMB drag rotate", 10, 48)
    love.graphics.print("LMB place  |  Shift+LMB remove  |  1-5 pick block", 10, 64)
    love.graphics.print("B brush  |  L line  |  R rect  |  Esc cancel/quit", 10, 80)
    love.graphics.print("Hold Ctrl/Cmd on 2nd click to axis-lock line/rect", 10, 96)
    local gridLabel = (self.grid and self.grid.modeName) and self.grid:modeName() or "off"
    love.graphics.print(string.format("G grid (%s)", gridLabel), 10, 112)

    love.graphics.pop()
end

return UI
