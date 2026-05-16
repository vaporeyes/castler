-- ABOUTME: Love2D entry point. Wires the voxel world, chunked renderer, camera,
-- ABOUTME: build manager, stability checker, particles, and UI overlay.

local VoxelWorld   = require("voxel_world")
local ChunkManager = require("chunk_manager")
local RTSCamera    = require("rts_camera")
local FlyCamera    = require("fly_camera")
local Stability    = require("structural_integrity")
local Particles    = require("particles")
local UndoManager  = require("undo_manager")
local BuildManager = require("build_manager")
local Grid         = require("grid")
local UI           = require("ui")
local Minimap      = require("minimap")
local Wad          = require("wad_loader")
local Voxelizer    = require("doom_voxelizer")
local WorldIO      = require("world_io")
local CastleGenerator = require("castle_generator")

local QUICKSAVE_FILE = "quicksave.castler"

local WORLD_W, WORLD_H, WORLD_D = 128, 64, 128

local world
local renderer
local camera         -- RTS orbit camera
local flyCam         -- First-person fly camera
local activeCam      -- Whichever one is currently driving view + input
local cameraMode = "rts"
local stability
local particles
local builder
local grid
local ui
local minimap
local undoManager
local lastImportMsg = nil
local lastImportMsgUntil = 0
local playerStart = nil  -- set by DOOM import; pressing F jumps fly cam here

-- Dropped-WAD state so levels can be browsed without re-dropping the file.
local wadData = nil      -- raw WAD bytes
local wadLevels = nil    -- ordered array of level marker names
local wadIndex = 1       -- currently voxelized level (1-based)

-- Castle generator config, browsable from the keyboard. Size presets feed
-- explicit dimensions into the generator; the seed still drives the smaller
-- per-castle variations, so (seed, size, keep) is fully deterministic.
local CASTLE_SIZES = {
    {name = "Small",  width = 26, depth = 24, wallHeight = 7,  towerHeight = 12, towerRadius = 3, wallThickness = 2},
    {name = "Medium", width = 42, depth = 38, wallHeight = 9,  towerHeight = 15, towerRadius = 4, wallThickness = 3},
    {name = "Large",  width = 64, depth = 56, wallHeight = 12, towerHeight = 20, towerRadius = 5, wallThickness = 3},
}
local CASTLE_KEEPS = {"square", "round"}
local castleConfig = { seed = 1000, sizeIndex = 2, keepIndex = 1 }

-- A day-arc of sun directions (point toward the sun). Cycled with J. Index 6
-- is the renderer's startup default, so we begin there for visual continuity.
local SUN_POSITIONS = {
    {name = "Dawn",      dir = { 0.85, 0.28,  0.12}},
    {name = "Morning",   dir = { 0.52, 0.70,  0.22}},
    {name = "Noon",      dir = { 0.08, 0.98,  0.05}},
    {name = "Afternoon", dir = {-0.50, 0.72, -0.25}},
    {name = "Dusk",      dir = {-0.85, 0.26, -0.15}},
    {name = "Default",   dir = { 0.40, 0.86,  0.30}},
}
local sunIndex = 6
local resetDefaultMap
local regenerateCastle
local saveQuicksave
local loadQuicksave
local setupMenu
local setPauseMenu

local function buildScene()
    -- Small reference castle near the world center so chunking is obvious.
    local cx = math.floor(WORLD_W / 2)
    local cz = math.floor(WORLD_D / 2)
    for x = cx - 2, cx + 2 do
        for z = cz - 2, cz + 2 do
            world:setBlock(x, 2, z, 1)
        end
    end
    for y = 3, 6 do
        world:setBlock(cx - 2, y, cz - 2, 2)
        world:setBlock(cx + 2, y, cz - 2, 2)
        world:setBlock(cx - 2, y, cz + 2, 2)
        world:setBlock(cx + 2, y, cz + 2, 2)
    end
    for x = cx - 2, cx + 2 do
        world:setBlock(x, 7, cz - 2, 1)
        world:setBlock(x, 7, cz + 2, 1)
    end
    for z = cz - 2, cz + 2 do
        world:setBlock(cx - 2, 7, z, 1)
        world:setBlock(cx + 2, 7, z, 1)
    end

    -- A few scattered pillars far enough apart to live in different chunks.
    local pillars = {
        {cx - 30, cz - 20, 12, 2},
        {cx + 28, cz - 24, 16, 1},
        {cx - 22, cz + 30, 10, 2},
        {cx + 32, cz + 30,  8, 1},
    }
    for _, p in ipairs(pillars) do
        local px, pz, h, id = p[1], p[2], p[3], p[4]
        for y = 2, h do world:setBlock(px, y, pz, id) end
    end
end

function love.load()
    world = VoxelWorld.new(WORLD_W, WORLD_H, WORLD_D)
    buildScene()
    renderer  = ChunkManager.new(world)
    camera    = RTSCamera.new({
        target   = {WORLD_W / 2, 0, WORLD_D / 2},
        distance = 60,
    })
    flyCam    = FlyCamera.new({pos = {WORLD_W / 2, 16, WORLD_D / 2}, world = world})
    activeCam = camera
    stability   = Stability.new(world)
    particles   = Particles.new()
    undoManager = UndoManager.new(world, renderer)
    builder     = BuildManager.new(world, renderer, camera, stability, particles, undoManager)
    grid        = Grid.new(world, camera, renderer.chunkSize)
    ui          = UI.new(world, builder, renderer, grid)
    minimap     = Minimap.new(world)
    setupMenu()
end

local function setCameraMode(mode)
    if mode == cameraMode then return end
    if mode == "fly" then
        local fromRTS = cameraMode == "rts"
        if playerStart then
            flyCam.pos = {playerStart.x, playerStart.y, playerStart.z}
            flyCam.yaw = playerStart.yaw
            flyCam.pitch = 0
        else
            flyCam:syncFromRTS(camera)
        end
        -- First-person defaults to WALK (gravity + collision) - the primary
        -- "explore the world on foot" case. Press N to switch to noclip when
        -- you need free movement for building. setCollide() settles the
        -- camera onto the ground at the just-set position.
        flyCam:setCollide(true)
        if fromRTS then
            flyCam:transitionFromRTS(camera, flyCam.pos, flyCam.yaw, flyCam.pitch)
        end
        flyCam:activate()
        activeCam = flyCam
    else
        flyCam:deactivate()
        activeCam = camera
    end
    cameraMode = mode
    builder.camera = activeCam
    grid.camera    = activeCam
    -- Any in-progress two-click op carried camera state; cancel for safety.
    builder:cancelPending()
end

-- Defined here (before any callback that references it) so the identifier
-- resolves to this local. `local function` declared after callbacks would
-- compile to a nil global lookup inside those callbacks.
local function showStatus(msg, seconds)
    lastImportMsg = msg
    lastImportMsgUntil = love.timer.getTime() + (seconds or 5)
end

function GetCameraMode() return cameraMode end

-- Reports the live castle config for the HUD panel.
function GetCastleInfo()
    return castleConfig.seed,
           CASTLE_SIZES[castleConfig.sizeIndex].name,
           CASTLE_KEEPS[castleConfig.keepIndex]
end

local function clearWadSelection()
    wadData, wadLevels, wadIndex = nil, nil, 1
end

-- Voxelize wadLevels[idx] from the retained WAD bytes. Shared by the initial
-- drop and the prev/next browse keys. Defined before regenerateCastle and the
-- input callbacks so those resolve it as this local, not a nil global.
local function loadWadLevel(idx)
    if not wadData or not wadLevels then return end
    local name = wadLevels[idx]
    local level, err = Wad.loadLevel(wadData, name)
    if not level then
        showStatus("Load " .. tostring(name) .. " failed: " .. tostring(err))
        return
    end

    local ok, result, importedStart = pcall(Voxelizer.import, world, renderer, level)
    if not ok then
        showStatus("Voxelize failed: " .. tostring(result))
        return
    end

    wadIndex = idx
    camera.targetPos = {world.width / 2, 0, world.depth / 2}
    camera.distance = math.max(world.width, world.depth) * 0.7
    playerStart = importedStart
    undoManager:clear()
    builder:cancelPending()
    if playerStart then
        flyCam.pos = {playerStart.x, playerStart.y, playerStart.z}
        flyCam.yaw = playerStart.yaw
        flyCam.pitch = 0
    else
        flyCam.pos = {world.width / 2, math.max(8, world.height * 0.3), world.depth / 2}
    end

    showStatus(string.format("%s  (%d/%d)  %d sectors  -  , / . to browse",
        level.name, idx, #wadLevels, #level.sectors), 8)
end

-- Step the WAD level selection (wraps). No-op if no WAD is loaded.
local function stepWadLevel(delta)
    if not wadLevels or #wadLevels == 0 then return false end
    local idx = (wadIndex - 1 + delta) % #wadLevels + 1
    loadWadLevel(idx)
    return true
end

function GetWadInfo()
    if wadLevels and wadLevels[wadIndex] then
        return wadLevels[wadIndex], wadIndex, #wadLevels
    end
    return nil
end

local function fillFloor()
    for x = 1, world.width do
        for z = 1, world.depth do
            world:setBlock(x, 1, z, 4)
        end
    end
end

local function resetTransientState()
    playerStart = nil
    clearWadSelection()
    undoManager:clear()
    builder:cancelPending()
    particles = Particles.new()
    builder.particles = particles
    camera.targetPos = {WORLD_W / 2, 0, WORLD_D / 2}
    camera.distance = 60
    flyCam.pos = {WORLD_W / 2, 16, WORLD_D / 2}
    flyCam.yaw = 0
    flyCam.pitch = 0
    flyCam.vy = 0
    if cameraMode ~= "rts" then
        setCameraMode("rts")
    end
end

resetDefaultMap = function()
    world:clear()
    fillFloor()
    buildScene()
    renderer:markAllDirty()
    renderer:flushDirty()
    resetTransientState()
    showStatus("New default map", 3)
end

-- Regenerate using the current (seed, size, keep) config and reset transient
-- state, matching the behavior of WAD import and .castler load.
regenerateCastle = function()
    local size = CASTLE_SIZES[castleConfig.sizeIndex]
    local keep = CASTLE_KEEPS[castleConfig.keepIndex]
    local result = CastleGenerator.generate(world, renderer, {
        seed          = castleConfig.seed,
        width         = size.width,
        depth         = size.depth,
        wallHeight    = size.wallHeight,
        towerHeight   = size.towerHeight,
        towerRadius   = size.towerRadius,
        wallThickness = size.wallThickness,
        keepStyle     = keep,
    })
    playerStart = nil
    clearWadSelection()
    undoManager:clear()
    builder:cancelPending()
    showStatus(string.format("Castle seed %d  -  %s  -  %s keep",
        result.seed, size.name, keep), 4)
end

saveQuicksave = function()
    local ok, size = WorldIO.save(world, QUICKSAVE_FILE)
    if ok then
        showStatus(string.format("Saved %s (%.1f KB)", QUICKSAVE_FILE, size / 1024), 4)
    else
        showStatus("Save failed: " .. tostring(size))
    end
end

loadQuicksave = function()
    if not love.filesystem.getInfo(QUICKSAVE_FILE) then
        showStatus("No quicksave found - press F5 first")
        return
    end
    local blob = love.filesystem.read(QUICKSAVE_FILE)
    local ok, err = WorldIO.load(world, renderer, blob)
    if ok then
        playerStart = nil
        clearWadSelection()
        undoManager:clear()
        builder:cancelPending()
        showStatus("Loaded " .. QUICKSAVE_FILE, 4)
    else
        showStatus("Load failed: " .. tostring(err))
    end
end

setupMenu = function()
    ui:setMenuItems({
        {label = "Resume", action = function() setPauseMenu(false) end},
        {label = "New Default Map", action = function()
            setPauseMenu(false)
            resetDefaultMap()
        end},
        {label = "New Castle", action = function()
            setPauseMenu(false)
            castleConfig.seed = love.math.random(1, 999999)
            regenerateCastle()
        end},
        {label = "Quicksave", action = function()
            setPauseMenu(false)
            saveQuicksave()
        end},
        {label = "Quickload", action = function()
            setPauseMenu(false)
            loadQuicksave()
        end},
        {label = "Quit", action = function() love.event.quit() end},
    })
end

setPauseMenu = function(open)
    ui:setMenuOpen(open)
    if love.mouse and love.mouse.setRelativeMode then
        love.mouse.setRelativeMode(false)
        if not open and cameraMode == "fly" then
            love.mouse.setRelativeMode(true)
        end
    end
end

function love.update(dt)
    if ui and ui:isMenuOpen() then return end
    activeCam:update(dt)
    builder:update(dt)
    particles:update(dt)
    minimap:update(dt)
end

-- Where the minimap marker sits + which way it faces, in world XZ.
local function minimapMarker()
    if cameraMode == "fly" then
        local fx, _, fz = flyCam:forward()
        return flyCam.pos[1], flyCam.pos[3], fx, fz
    end
    local t = camera.cTarget
    local e = camera:eye()
    return t[1], t[3], t[1] - e[1], t[3] - e[3]
end

function love.draw()
    love.graphics.clear(0.14, 0.16, 0.23, 1, true, true)

    local w, h = love.graphics.getDimensions()
    local view = activeCam:viewMatrix()
    local proj = activeCam:projectionMatrix(w / h)

    renderer:draw(view, proj)
    grid:draw()
    particles:draw(view, proj)
    builder:draw()
    ui:draw()
    local mmx, mmz, mmdx, mmdz = minimapMarker()
    minimap:draw(mmx, mmz, mmdx, mmdz)
end

local function modHeld()
    return love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")
        or love.keyboard.isDown("lgui")  or love.keyboard.isDown("rgui")
end

local function shiftDown()
    return love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")
end

function love.keypressed(key)
    if key == "escape" then
        if ui and ui:isMenuOpen() then
            setPauseMenu(false)
        elseif not builder:cancelPending() then
            setPauseMenu(true)
        end
        return
    end
    if ui and ui:isMenuOpen() then return end
    if key == "z" and modHeld() then
        if stability and stability.hasPending and stability:hasPending() then
            showStatus("Stability resolving - try undo in a moment", 2)
            return
        end
        if shiftDown() then
            local ok, n = undoManager:redo()
            showStatus(ok and string.format("Redo (%d cells)", n) or "Nothing to redo", 2)
        else
            local ok, n = undoManager:undo()
            showStatus(ok and string.format("Undo (%d cells)", n) or "Nothing to undo", 2)
        end
        return
    end
    if key == "y" and modHeld() then
        if stability and stability.hasPending and stability:hasPending() then
            showStatus("Stability resolving - try redo in a moment", 2)
            return
        end
        local ok, n = undoManager:redo()
        showStatus(ok and string.format("Redo (%d cells)", n) or "Nothing to redo", 2)
        return
    end
    if key == "b" then builder:setTool("brush");  return end
    if key == "l" then builder:setTool("line");   return end
    if key == "r" then builder:setTool("rect");   return end
    if key == "x" then builder:setTool("box");    return end
    if key == "o" then builder:setTool("sphere"); return end
    if key == "g" then grid:cycle();              return end
    if key == "m" then
        local on = minimap:toggle()
        showStatus("Minimap " .. (on and "on" or "off"), 2)
        return
    end
    if key == "," then
        if not stepWadLevel(-1) then showStatus("No WAD loaded", 2) end
        return
    end
    if key == "." then
        if not stepWadLevel(1) then showStatus("No WAD loaded", 2) end
        return
    end
    if key == "c" then
        castleConfig.seed = love.math.random(1, 999999)
        regenerateCastle()
        return
    end
    if key == "[" then
        castleConfig.seed = math.max(0, castleConfig.seed - 1)
        regenerateCastle()
        return
    end
    if key == "]" then
        castleConfig.seed = castleConfig.seed + 1
        regenerateCastle()
        return
    end
    if key == "v" then
        castleConfig.sizeIndex = castleConfig.sizeIndex % #CASTLE_SIZES + 1
        regenerateCastle()
        return
    end
    if key == "k" then
        castleConfig.keepIndex = castleConfig.keepIndex % #CASTLE_KEEPS + 1
        regenerateCastle()
        return
    end
    if key == "f" then
        setCameraMode(cameraMode == "fly" and "rts" or "fly")
        return
    end
    if key == "n" then
        -- Toggle walk (gravity + collision) vs noclip free-fly. Only meaningful
        -- in first-person; harmless otherwise.
        flyCam:setCollide(not flyCam.collide)
        showStatus("First-person: " .. flyCam:modeName(), 2)
        return
    end
    if key == "t" then
        local on = builder:toggleBuild()
        showStatus("Building " .. (on and "ON" or "OFF - explore only"), 2)
        return
    end
    if key == "e" then
        local rm = builder:toggleRemoveMode()
        showStatus(rm and "Subtract mode (all tools remove)"
                       or "Add mode (all tools place)", 2)
        return
    end
    if key == "j" then
        sunIndex = sunIndex % #SUN_POSITIONS + 1
        local s = SUN_POSITIONS[sunIndex]
        renderer:setSun(s.dir[1], s.dir[2], s.dir[3])
        showStatus("Sun: " .. s.name, 2)
        return
    end
    if key == "f5" then
        saveQuicksave()
        return
    end
    if key == "f9" then
        loadQuicksave()
        return
    end

    local n = tonumber(key)
    if n then
        local id = ui and ui.hotbarIdForSlot and ui:hotbarIdForSlot(n)
        if not id then
            local ids = world:placeableBlockIds()
            id = ids[n]
        end
        if id then builder:setActiveBlock(id) end
    end
end

function love.mousepressed(x, y, b)
    if ui and ui:menuMousepressed(x, y, b) then return end
    if ui and ui:isMenuOpen() then return end
    if ui and ui:mousepressed(x, y, b) then return end
    if b == 3 then  -- middle click = eyedropper
        local picked = builder:eyedrop()
        if picked then showStatus("Picked block " .. tostring(picked), 2) end
        return
    end
    if b == 2 then  -- right click = remove the targeted block
        builder:removeAtCursor()
        return
    end
    -- Left click: camera self-gates orbit on Alt; builder skips Alt+LMB.
    activeCam:mousepressed(x, y, b)
    builder:mousepressed(x, y, b)
end
function love.mousereleased(x, y, b)
    if ui and ui:isMenuOpen() then return end
    if ui then ui:mousereleased(x, y, b) end
    activeCam:mousereleased(x, y, b)
end
function love.mousemoved(x, y, dx, dy)
    if ui and ui:isMenuOpen() then return end
    if ui and ui:mousemoved(x, y, dx, dy) then return end
    activeCam:mousemoved(x, y, dx, dy)
end
function love.wheelmoved(x, y)
    if ui and ui:isMenuOpen() then return end
    if ui and ui:wheelmoved(x, y) then return end
    activeCam:wheelmoved(x, y)
end

function love.filedropped(file)
    file:open("r")
    local data = file:read()
    file:close()

    -- Castler save file: load it and we're done.
    if WorldIO.isSave(data) then
        local ok, err = WorldIO.load(world, renderer, data)
        if ok then
            playerStart = nil
            clearWadSelection()
            undoManager:clear()
            showStatus("Loaded " .. file:getFilename(), 5)
        else
            showStatus("Load failed: " .. tostring(err))
        end
        return
    end

    local levels, lerr = Wad.listLevels(data)
    if not levels then
        showStatus("Import failed: " .. tostring(lerr))
        return
    end
    wadData = data
    wadLevels = levels
    loadWadLevel(1)
end

-- Expose a status getter so the UI can render the import banner.
function GetImportStatus()
    if lastImportMsg and love.timer.getTime() < lastImportMsgUntil then
        return lastImportMsg
    end
    return nil
end
