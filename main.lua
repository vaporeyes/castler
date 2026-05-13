-- ABOUTME: Love2D entry point. Wires the voxel world, chunked renderer, camera,
-- ABOUTME: build manager, stability checker, particles, and UI overlay.

local VoxelWorld   = require("voxel_world")
local ChunkManager = require("chunk_manager")
local RTSCamera    = require("rts_camera")
local Stability    = require("structural_integrity")
local Particles    = require("particles")
local BuildManager = require("build_manager")
local Grid         = require("grid")
local UI           = require("ui")

local WORLD_W, WORLD_H, WORLD_D = 128, 64, 128

local world
local renderer
local camera
local stability
local particles
local builder
local grid
local ui

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
    stability = Stability.new(world)
    particles = Particles.new()
    builder   = BuildManager.new(world, renderer, camera, stability, particles)
    grid      = Grid.new(world, camera, renderer.chunkSize)
    ui        = UI.new(world, builder, renderer, grid)
end

function love.update(dt)
    camera:update(dt)
    builder:update(dt)
    particles:update(dt)
end

function love.draw()
    love.graphics.clear(0.10, 0.12, 0.18, 1, true, true)

    local w, h = love.graphics.getDimensions()
    local view = camera:viewMatrix()
    local proj = camera:projectionMatrix(w / h)

    renderer:draw(view, proj)
    grid:draw()
    particles:draw(view, proj)
    builder:draw()
    ui:draw()
end

function love.keypressed(key)
    if key == "escape" then
        if not builder:cancelPending() then love.event.quit() end
        return
    end
    if key == "b" then builder:setTool("brush"); return end
    if key == "l" then builder:setTool("line");  return end
    if key == "r" then builder:setTool("rect");  return end
    if key == "g" then grid:cycle();              return end

    local n = tonumber(key)
    if n and n >= 1 and n <= 5 then
        builder:setActiveBlock(n)
    end
end

function love.mousepressed(x, y, b)   camera:mousepressed(x, y, b); builder:mousepressed(x, y, b) end
function love.mousereleased(x, y, b)  camera:mousereleased(x, y, b) end
function love.mousemoved(x, y, dx, dy) camera:mousemoved(x, y, dx, dy) end
function love.wheelmoved(x, y)        camera:wheelmoved(x, y)        end
