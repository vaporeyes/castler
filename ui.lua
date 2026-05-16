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
local MENU_W = 300
local MENU_PAD = 14
local MENU_BUTTON_H = 34
local MENU_GAP = 8

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
    self.panelCollapsed = false
    self.panelToggleRect = nil
    self.draggingPanel = false
    self.dragOffsetX = 0
    self.dragOffsetY = 0
    self.hotbarOffset = 1
    self.hotbarIds = {}
    self.hotbarRect = nil
    self.menuOpen = false
    self.menuItems = {}
    self.menuButtons = {}
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
    if self.panelCollapsed then
        height = PANEL_HEADER_H
    end
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

    local toggleSize = 20
    local toggleX = x + width - PANEL_PAD_X - toggleSize
    local toggleY = y + 5
    self.panelToggleRect = {x = toggleX, y = toggleY, w = toggleSize, h = toggleSize}
    love.graphics.setColor(0.48, 0.55, 0.68, 0.28)
    love.graphics.rectangle("fill", toggleX, toggleY, toggleSize, toggleSize, 4, 4)
    love.graphics.setColor(0.80, 0.86, 0.96, 0.95)
    love.graphics.setLineWidth(1.5)
    local cy = toggleY + toggleSize * 0.5
    love.graphics.line(toggleX + 5, cy, toggleX + toggleSize - 5, cy)
    if self.panelCollapsed then
        local cx = toggleX + toggleSize * 0.5
        love.graphics.line(cx, toggleY + 5, cx, toggleY + toggleSize - 5)
    end

    if self.panelCollapsed then return end

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
    if self.hotbarRect and pointInRect(x, y,
        self.hotbarRect.x, self.hotbarRect.y, self.hotbarRect.w, self.hotbarRect.h) then
        local slot = math.floor((x - self.hotbarRect.x) / (SLOT_SIZE + SLOT_GAP)) + 1
        local id = self.hotbarIds[slot]
        if id then self.builder:setActiveBlock(id) end
        return true
    end
    if self.panelToggleRect and pointInRect(x, y,
        self.panelToggleRect.x, self.panelToggleRect.y,
        self.panelToggleRect.w, self.panelToggleRect.h) then
        self.panelCollapsed = not self.panelCollapsed
        return true
    end
    if pointInRect(x, y, self.panelX, self.panelY, self.panelW, self.panelH) then
        self.draggingPanel = true
        self.dragOffsetX = x - self.panelX
        self.dragOffsetY = y - self.panelY
        return true
    end
    return false
end

function UI:wheelmoved(_, y)
    if not self.hotbarRect or not love.mouse then return false end
    local mx, my = love.mouse.getPosition()
    if not pointInRect(mx, my, self.hotbarRect.x, self.hotbarRect.y, self.hotbarRect.w, self.hotbarRect.h) then
        return false
    end
    local ids = self.world.placeableBlockIds and self.world:placeableBlockIds() or {}
    local visible = self.hotbarRect.visible or #ids
    local maxOffset = math.max(1, #ids - visible + 1)
    self.hotbarOffset = clamp(self.hotbarOffset - y, 1, maxOffset)
    return true
end

function UI:hotbarIdForSlot(slot)
    return self.hotbarIds and self.hotbarIds[slot] or nil
end

function UI:setMenuItems(items)
    self.menuItems = items or {}
end

function UI:toggleMenu()
    self.menuOpen = not self.menuOpen
    return self.menuOpen
end

function UI:setMenuOpen(open)
    self.menuOpen = open and true or false
end

function UI:isMenuOpen()
    return self.menuOpen
end

function UI:mousereleased(_, _, button)
    if button == 1 then
        self.draggingPanel = false
    end
end

function UI:menuMousepressed(x, y, button)
    if not self.menuOpen then return false end
    if button ~= 1 then return true end
    for i = 1, #self.menuButtons do
        local b = self.menuButtons[i]
        if pointInRect(x, y, b.x, b.y, b.w, b.h) then
            local item = self.menuItems[i]
            if item and item.action then item.action() end
            return true
        end
    end
    return true
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

local function blockName(world, id)
    if world and world.blockName then return world:blockName(id) end
    return "#" .. tostring(id)
end

local function drawMenu(self, sw, sh)
    if not self.menuOpen then return end

    love.graphics.setColor(0.02, 0.03, 0.05, 0.58)
    love.graphics.rectangle("fill", 0, 0, sw, sh)

    local itemCount = #self.menuItems
    local menuH = MENU_PAD * 2 + 28 + itemCount * MENU_BUTTON_H
        + math.max(0, itemCount - 1) * MENU_GAP
    local x = math.floor((sw - MENU_W) * 0.5)
    local y = math.floor((sh - menuH) * 0.5)

    love.graphics.setColor(0, 0, 0, 0.30)
    love.graphics.rectangle("fill", x + 5, y + 6, MENU_W, menuH, PANEL_RADIUS, PANEL_RADIUS)
    love.graphics.setColor(0.06, 0.08, 0.12, 0.96)
    love.graphics.rectangle("fill", x, y, MENU_W, menuH, PANEL_RADIUS, PANEL_RADIUS)
    love.graphics.setColor(0.38, 0.80, 1.00, 0.95)
    love.graphics.rectangle("fill", x, y, MENU_W, 2, PANEL_RADIUS, PANEL_RADIUS)
    love.graphics.setColor(0.20, 0.26, 0.37, 0.85)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, MENU_W - 1, menuH - 1, PANEL_RADIUS, PANEL_RADIUS)

    love.graphics.setColor(0.95, 0.97, 1, 1)
    love.graphics.printf("Menu", x, y + MENU_PAD - 2, MENU_W, "center")

    local buttonY = y + MENU_PAD + 30
    self.menuButtons = {}
    for i = 1, itemCount do
        local item = self.menuItems[i]
        local bx = x + MENU_PAD
        local by = buttonY + (i - 1) * (MENU_BUTTON_H + MENU_GAP)
        local bw = MENU_W - MENU_PAD * 2
        self.menuButtons[i] = {x = bx, y = by, w = bw, h = MENU_BUTTON_H}
        love.graphics.setColor(0.12, 0.16, 0.24, 0.96)
        love.graphics.rectangle("fill", bx, by, bw, MENU_BUTTON_H, 5, 5)
        love.graphics.setColor(0.28, 0.36, 0.50, 0.90)
        love.graphics.rectangle("line", bx + 0.5, by + 0.5, bw - 1, MENU_BUTTON_H - 1, 5, 5)
        love.graphics.setColor(0.88, 0.92, 1.00, 1)
        love.graphics.printf(item.label, bx, by + 9, bw, "center")
    end
end

function UI:draw()
    love.graphics.push("all")
    love.graphics.setDepthMode()

    local sw, sh = love.graphics.getDimensions()
    local palette = self.world.PALETTE

    local allHotbarIds = self.world.placeableBlockIds and self.world:placeableBlockIds() or {}
    local visibleSlots = math.max(1, math.min(#allHotbarIds,
        math.floor((sw - 32 + SLOT_GAP) / (SLOT_SIZE + SLOT_GAP))))
    local maxOffset = math.max(1, #allHotbarIds - visibleSlots + 1)
    self.hotbarOffset = clamp(self.hotbarOffset, 1, maxOffset)

    local activeIndex = nil
    for i = 1, #allHotbarIds do
        if allHotbarIds[i] == self.builder.activeBlockId then
            activeIndex = i
            break
        end
    end
    if activeIndex then
        if activeIndex < self.hotbarOffset then
            self.hotbarOffset = activeIndex
        elseif activeIndex >= self.hotbarOffset + visibleSlots then
            self.hotbarOffset = activeIndex - visibleSlots + 1
        end
    end

    local hotbarIds = {}
    for slot = 1, visibleSlots do
        hotbarIds[slot] = allHotbarIds[self.hotbarOffset + slot - 1]
    end
    self.hotbarIds = hotbarIds

    local totalWidth = #hotbarIds * SLOT_SIZE + math.max(0, #hotbarIds - 1) * SLOT_GAP
    local startX = (sw - totalWidth) * 0.5
    local y = sh - SLOT_SIZE - 16
    self.hotbarRect = {x = startX, y = y, w = totalWidth, h = SLOT_SIZE, visible = visibleSlots}

    for slot = 1, #hotbarIds do
        local id = hotbarIds[slot]
        local color = palette[id]
        if color then
            local x = startX + (slot - 1) * (SLOT_SIZE + SLOT_GAP)
            drawSlot(x, y, color, id == self.builder.activeBlockId, tostring(slot))
        end
    end

    -- Status line above the hotbar: active block + tool.
    local active = self.builder.activeBlockId
    local name = blockName(self.world, active)
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

    -- Hover readout: what the build ray is currently pointing at.
    local h = self.builder and self.builder.hit
    if h then
        local nm = blockName(self.world, h.id)
        local line = string.format("Aim (%d,%d,%d)  %s [%d]", h.x, h.y, h.z, nm, h.id)
        if self.renderer and self.renderer.chunkCoordsOf then
            local ccx, ccy, ccz = self.renderer:chunkCoordsOf(h.x, h.y, h.z)
            line = line .. string.format("  chunk (%d,%d,%d)", ccx, ccy, ccz)
        end
        infoLines[#infoLines + 1] = line
    else
        infoLines[#infoLines + 1] = "Aim (sky)"
    end
    local mode = GetCameraMode and GetCameraMode() or "rts"
    if mode == "fly" then
        local cam = self.builder and self.builder.camera
        local fpMode = (cam and cam.modeName) and cam:modeName() or "noclip"
        if fpMode == "walk" then
            infoLines[#infoLines + 1] = "WALK - mouse looks  |  WASD move  |  Space jump  |  Shift run"
            infoLines[#infoLines + 1] = "LMB place  |  RMB remove  |  N noclip  |  F returns to RTS"
        else
            infoLines[#infoLines + 1] = "NOCLIP - mouse looks  |  WASD fly  |  Space/Ctrl up-down"
            infoLines[#infoLines + 1] = "LMB place  |  RMB remove  |  N walk  |  F returns to RTS"
        end
    else
        infoLines[#infoLines + 1] = "WASD pan  |  scroll zoom  |  Alt+drag rotate  |  F walk (1st person)"
        infoLines[#infoLines + 1] = "LMB place  |  RMB remove  |  Mid-click pick  |  1-5 block"
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
    infoLines[#infoLines + 1] = string.format("G grid (%s)  |  J cycle sun  |  M minimap", gridLabel)
    infoLines[#infoLines + 1] = "Drop .WAD to import DOOM  |  Drop .castler to load save"
    if GetWadInfo then
        local lvl, idx, total = GetWadInfo()
        if lvl then
            infoLines[#infoLines + 1] = string.format(
                "WAD level: %s  (%d/%d)  -  , prev  /  . next", lvl, idx, total)
        end
    end
    infoLines[#infoLines + 1] = "F5 quicksave  |  F9 quickload  |  Ctrl+Z undo  |  Ctrl+Shift+Z redo"
    infoLines[#infoLines + 1] = "Up/Down = adjust height during pending box/sphere/line"
    drawInfoPanel(self, infoLines)

    -- First-person crosshair: the build/eyedrop ray fires from screen center,
    -- so show where that is.
    if mode == "fly" then
        local cx, cy = sw * 0.5, sh * 0.5
        love.graphics.setColor(1, 1, 1, 0.55)
        love.graphics.setLineWidth(1)
        love.graphics.line(cx - 7, cy, cx - 2, cy)
        love.graphics.line(cx + 2, cy, cx + 7, cy)
        love.graphics.line(cx, cy - 7, cx, cy - 2)
        love.graphics.line(cx, cy + 2, cx, cy + 7)
        love.graphics.setColor(1, 1, 1, 0.85)
        love.graphics.circle("fill", cx, cy, 1.2)
    end

    -- Transient import banner.
    if GetImportStatus then
        local msg = GetImportStatus()
        if msg then
            love.graphics.setColor(1, 0.95, 0.55, 1)
            love.graphics.printf(msg, 0, sh * 0.5 - 90, sw, "center")
        end
    end

    drawMenu(self, sw, sh)

    love.graphics.pop()
end

return UI
