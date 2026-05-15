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
local undoManager
local lastImportMsg = nil
local lastImportMsgUntil = 0
local playerStart = nil  -- set by DOOM import; pressing F jumps fly cam here

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
end

local function setCameraMode(mode)
    if mode == cameraMode then return end
    if mode == "fly" then
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

-- Regenerate using the current (seed, size, keep) config and reset transient
-- state, matching the behavior of WAD import and .castler load.
local function regenerateCastle()
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
    undoManager:clear()
    builder:cancelPending()
    showStatus(string.format("Castle seed %d  -  %s  -  %s keep",
        result.seed, size.name, keep), 4)
end

function love.update(dt)
    activeCam:update(dt)
    builder:update(dt)
    particles:update(dt)
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
        if not builder:cancelPending() then love.event.quit() end
        return
    end
    if key == "z" and modHeld() then
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
    if key == "f5" then
        local ok, size = WorldIO.save(world, QUICKSAVE_FILE)
        if ok then
            showStatus(string.format("Saved %s (%.1f KB)", QUICKSAVE_FILE, size / 1024), 4)
        else
            showStatus("Save failed: " .. tostring(size))
        end
        return
    end
    if key == "f9" then
        if not love.filesystem.getInfo(QUICKSAVE_FILE) then
            showStatus("No quicksave found - press F5 first")
            return
        end
        local blob = love.filesystem.read(QUICKSAVE_FILE)
        local ok, err = WorldIO.load(world, renderer, blob)
        if ok then
            playerStart = nil  -- save doesn't preserve player-start metadata
            undoManager:clear()
            showStatus("Loaded " .. QUICKSAVE_FILE, 4)
        else
            showStatus("Load failed: " .. tostring(err))
        end
        return
    end

    local n = tonumber(key)
    if n and n >= 1 and n <= 5 then
        builder:setActiveBlock(n)
    end
end

function love.mousepressed(x, y, b)
    if ui and ui:mousepressed(x, y, b) then return end
    activeCam:mousepressed(x, y, b)
    builder:mousepressed(x, y, b)
end
function love.mousereleased(x, y, b)
    if ui then ui:mousereleased(x, y, b) end
    activeCam:mousereleased(x, y, b)
end
function love.mousemoved(x, y, dx, dy)
    if ui and ui:mousemoved(x, y, dx, dy) then return end
    activeCam:mousemoved(x, y, dx, dy)
end
function love.wheelmoved(x, y)        activeCam:wheelmoved(x, y)        end

function love.filedropped(file)
    file:open("r")
    local data = file:read()
    file:close()

    -- Castler save file: load it and we're done.
    if WorldIO.isSave(data) then
        local ok, err = WorldIO.load(world, renderer, data)
        if ok then
            playerStart = nil
            undoManager:clear()
            showStatus("Loaded " .. file:getFilename(), 5)
        else
            showStatus("Load failed: " .. tostring(err))
        end
        return
    end

    local level, err = Wad.loadLevel(data)
    if not level then
        showStatus("Import failed: " .. tostring(err))
        return
    end

    local ok, result, importedStart = pcall(Voxelizer.import, world, renderer, level)
    if not ok then
        showStatus("Voxelize failed: " .. tostring(result))
        return
    end

    -- Recenter cameras on the imported map.
    camera.targetPos = {world.width / 2, 0, world.depth / 2}
    camera.distance = math.max(world.width, world.depth) * 0.7
    playerStart = importedStart  -- nil if the WAD had no THING type 1
    undoManager:clear()
    if playerStart then
        flyCam.pos = {playerStart.x, playerStart.y, playerStart.z}
        flyCam.yaw = playerStart.yaw
        flyCam.pitch = 0
    else
        flyCam.pos = {world.width / 2, math.max(8, world.height * 0.3), world.depth / 2}
    end

    showStatus(string.format("Imported %s (%d sectors, %d linedefs)",
        level.name, #level.sectors, #level.linedefs), 8)
end

-- Expose a status getter so the UI can render the import banner.
function GetImportStatus()
    if lastImportMsg and love.timer.getTime() < lastImportMsgUntil then
        return lastImportMsg
    end
    return nil
end
