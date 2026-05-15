-- ABOUTME: 2D HUD overlay - hotbar/palette, status line, control hints. Drawn
-- ABOUTME: with depth testing disabled so it sits on top of the 3D scene.

local UI = {}
UI.__index = UI

local SLOT_SIZE = 48
local SLOT_GAP  = 6
local PANEL_PAD_X = 14
local PANEL_PAD_Y = 12
local PANEL_ROW_GAP = 5
local PANEL_RADIUS = 8
local PANEL_MIN_WIDTH = 340
local PANEL_TITLE = "Castler"
local PANEL_HEADER_H = 30
local PANEL_FOOTER_GLOW = 18
-- IDs above this are voxelizer-managed (per-sector lit colors from DOOM
-- imports). The hotbar should never grow to show them.
local HOTBAR_MAX_ID = 5
local BLOCK_NAMES = {
    [1] = "Stone",
    [2] = "Wood",
    [3] = "Dirt",
    [4] = "Grass",
    [5] = "Sand",
}

local TOOL_LABELS = {
    brush  = "Brush",
    line   = "Line",
    rect   = "Rect",
    box    = "Box",
    sphere = "Sphere",
}

function UI.new(world, builder, renderer, grid)
    local self = setmetatable({}, UI)
    self.world = world
    self.builder = builder
    self.renderer = renderer
    self.grid = grid
    self.panelX = 14
    self.panelY = 14
    self.panelW = PANEL_MIN_WIDTH
    self.panelH = 1
    self.draggingPanel = false
    self.dragOffsetX = 0
    self.dragOffsetY = 0
    return self
end

local function measureInfoPanel(lines)
    local font = love.graphics.getFont()
    local lineHeight = font:getHeight()
    local width = math.max(PANEL_MIN_WIDTH, font:getWidth(PANEL_TITLE))
    for i = 1, #lines do
        width = math.max(width, font:getWidth(lines[i]))
    end
    width = width + PANEL_PAD_X * 2

    local height = PANEL_HEADER_H + PANEL_PAD_Y * 2
        + #lines * lineHeight + math.max(0, #lines - 1) * PANEL_ROW_GAP
    return width, height, lineHeight
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function pointInRect(px, py, x, y, w, h)
    return px >= x and px <= x + w and py >= y and py <= y + h
end

local function drawInfoPanel(self, lines)
    local width, height, lineHeight = measureInfoPanel(lines)
    local sw, sh = love.graphics.getDimensions()
    local x = clamp(self.panelX, 0, math.max(0, sw - width))
    local y = clamp(self.panelY, 0, math.max(0, sh - height))
    self.panelX = x
    self.panelY = y
    self.panelW = width
    self.panelH = height

    love.graphics.setColor(0, 0, 0, 0.18)
    love.graphics.rectangle("fill", x + 7, y + 8, width, height, PANEL_RADIUS, PANEL_RADIUS)
    love.graphics.setColor(0, 0, 0, 0.16)
    love.graphics.rectangle("fill", x + 3, y + 4, width, height, PANEL_RADIUS, PANEL_RADIUS)

    love.graphics.setColor(0.05, 0.07, 0.11, 0.90)
    love.graphics.rectangle("fill", x, y, width, height, PANEL_RADIUS, PANEL_RADIUS)

    love.graphics.setColor(0.10, 0.13, 0.20, 0.96)
    love.graphics.rectangle("fill", x, y, width, PANEL_HEADER_H, PANEL_RADIUS, PANEL_RADIUS)
    love.graphics.setColor(0.10, 0.13, 0.20, 0.96)
    love.graphics.rectangle("fill", x, y + PANEL_HEADER_H - PANEL_RADIUS, width, PANEL_RADIUS)

    love.graphics.setColor(0.38, 0.80, 1.00, 0.95)
    love.graphics.rectangle("fill", x, y, width, 2, PANEL_RADIUS, PANEL_RADIUS)

    love.graphics.setColor(0.20, 0.26, 0.37, 0.80)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, width - 1, height - 1, PANEL_RADIUS, PANEL_RADIUS)

    love.graphics.setColor(0.95, 0.97, 1, 1)
    love.graphics.print(PANEL_TITLE, x + PANEL_PAD_X, y + 8)

    local dotY = y + 14
    local dotX = x + width - PANEL_PAD_X - 26
    love.graphics.setColor(0.48, 0.55, 0.68, 0.90)
    love.graphics.circle("fill", dotX, dotY, 2.2)
    love.graphics.circle("fill", dotX + 10, dotY, 2.2)
    love.graphics.circle("fill", dotX + 20, dotY, 2.2)

    love.graphics.setColor(0.18, 0.23, 0.33, 0.95)
    love.graphics.rectangle("fill", x, y + PANEL_HEADER_H, width, 1)

    love.graphics.setColor(0.18, 0.45, 0.60, 0.10)
    love.graphics.rectangle("fill", x + 1, y + height - PANEL_FOOTER_GLOW, width - 2, PANEL_FOOTER_GLOW - 1, 0, 0)

    love.graphics.setColor(0.82, 0.87, 0.96, 1)
    local lineY = y + PANEL_HEADER_H + PANEL_PAD_Y
    for i = 1, #lines do
        if i == 1 or i == 2 then
            love.graphics.setColor(0.58, 0.88, 1.00, 1)
        else
            love.graphics.setColor(0.82, 0.87, 0.96, 1)
        end
        love.graphics.print(lines[i], x + PANEL_PAD_X, lineY)
        lineY = lineY + lineHeight + PANEL_ROW_GAP
    end
end

function UI:mousepressed(x, y, button)
    if button ~= 1 then return false end
    if pointInRect(x, y, self.panelX, self.panelY, self.panelW, self.panelH) then
        self.draggingPanel = true
        self.dragOffsetX = x - self.panelX
        self.dragOffsetY = y - self.panelY
        return true
    end
    return false
end

function UI:mousereleased(_, _, button)
    if button == 1 then
        self.draggingPanel = false
    end
end

function UI:mousemoved(x, y)
    if not self.draggingPanel then return false end
    local sw, sh = love.graphics.getDimensions()
    self.panelX = clamp(x - self.dragOffsetX, 0, math.max(0, sw - self.panelW))
    self.panelY = clamp(y - self.dragOffsetY, 0, math.max(0, sh - self.panelH))
    return true
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

    -- Hotbar only ever shows the user-pickable IDs (1..HOTBAR_MAX_ID).
    -- Sector-specific palette entries injected by the DOOM voxelizer live
    -- well above this range and are not exposed for placement.
    local maxId = 0
    for id in pairs(palette) do
        if id <= HOTBAR_MAX_ID and id > maxId then maxId = id end
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
    local pendingTag = ""
    if self.builder.pending then
        pendingTag = "  (anchor set - click end point)"
        if self.builder.heightOffset and self.builder.heightOffset ~= 0 then
            pendingTag = pendingTag .. string.format("  height %+d", self.builder.heightOffset)
        end
    end
    local statusY = y - 22
    if self.builder.buildEnabled == false then
        love.graphics.setColor(0.65, 0.70, 0.80, 1)
        love.graphics.printf("Building OFF  -  explore only  (T to enable)",
            0, statusY, sw, "center")
    elseif self.builder.removeMode then
        love.graphics.setColor(1, 0.45, 0.40, 1)
        love.graphics.printf("SUBTRACT  -  " .. toolLabel .. pendingTag,
            0, statusY, sw, "center")
    else
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf(name .. "  -  " .. toolLabel .. pendingTag,
            0, statusY, sw, "center")
    end

    local infoLines = {
        string.format("FPS %d", love.timer.getFPS()),
    }
    if self.renderer and self.renderer.getStats then
        local v, t, drawn, total = self.renderer:getStats()
        infoLines[#infoLines + 1] = string.format("Chunks %d/%d   Tris %d", drawn, total, t)
    end
    local mode = GetCameraMode and GetCameraMode() or "rts"
    if mode == "fly" then
        local cam = self.builder and self.builder.camera
        local fpMode = (cam and cam.modeName) and cam:modeName() or "noclip"
        if fpMode == "walk" then
            infoLines[#infoLines + 1] = "WALK - mouse looks  |  WASD move  |  Space jump  |  Shift run"
            infoLines[#infoLines + 1] = "N = noclip  |  F returns to RTS"
        else
            infoLines[#infoLines + 1] = "NOCLIP - mouse looks  |  WASD fly  |  Space/Ctrl up-down"
            infoLines[#infoLines + 1] = "Shift = boost  |  N = walk  |  F returns to RTS"
        end
    else
        infoLines[#infoLines + 1] = "WASD pan  |  scroll zoom  |  RMB drag rotate  |  F walk (1st person)"
        infoLines[#infoLines + 1] = "LMB place  |  Shift+LMB remove  |  1-5 pick block"
    end
    infoLines[#infoLines + 1] = "B brush  |  L line  |  R rect  |  X box  |  O sphere"
    infoLines[#infoLines + 1] = "E add/subtract  |  T build on/off  |  Shift inverts add/subtract"
    infoLines[#infoLines + 1] = "Hold Ctrl/Cmd on 2nd click to axis-lock line/rect"
    if GetCastleInfo then
        local seed, sizeName, keepName = GetCastleInfo()
        infoLines[#infoLines + 1] = string.format(
            "Castle: seed %d  |  %s  |  %s keep", seed, sizeName, keepName)
        infoLines[#infoLines + 1] = "C random  |  [ / ] seed  |  V size  |  K keep"
    end
    local gridLabel = (self.grid and self.grid.modeName) and self.grid:modeName() or "off"
    infoLines[#infoLines + 1] = string.format("G grid (%s)", gridLabel)
    infoLines[#infoLines + 1] = "Drop .WAD to import DOOM  |  Drop .castler to load save"
    infoLines[#infoLines + 1] = "F5 quicksave  |  F9 quickload  |  Ctrl+Z undo  |  Ctrl+Shift+Z redo"
    infoLines[#infoLines + 1] = "Up/Down = adjust height during pending box/sphere/line"
    drawInfoPanel(self, infoLines)

    -- Transient import banner.
    if GetImportStatus then
        local msg = GetImportStatus()
        if msg then
            love.graphics.setColor(1, 0.95, 0.55, 1)
            love.graphics.printf(msg, 0, sh * 0.5 - 90, sw, "center")
        end
    end

    love.graphics.pop()
end

return UI
