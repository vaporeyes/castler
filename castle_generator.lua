-- ABOUTME: Procedural castle autobuilder using reusable voxel operations.
-- ABOUTME: Generates a deterministic walled castle layout from a seed.

local Ops = require("voxel_ops")

local CastleGenerator = {}

local STONE = 1
local WOOD  = 2
local GRASS = 4
local SAND  = 5

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function choice(rng, minValue, maxValue)
    return rng(minValue, maxValue)
end

local function resetWorld(world)
    world:clear()
    Ops.floor(world, GRASS)
end

local function clearDoor(world, x1, z1, x2, z2, topY)
    Ops.clearBox(world, x1, 2, z1, x2, topY, z2)
end

local function addTower(world, x, z, radius, wallHeight, towerHeight)
    Ops.cylinder(world, x, z, radius, 2, towerHeight, STONE, false)
    Ops.cylinder(world, x, z, math.max(1, radius - 2), 3, towerHeight - 1, 0, false)
    Ops.cylinder(world, x, z, radius, towerHeight + 1, towerHeight + 1, STONE, true)

    for dx = -radius, radius, 2 do
        Ops.fillBox(world, x + dx, towerHeight + 2, z - radius, x + dx, towerHeight + 2, z - radius, STONE)
        Ops.fillBox(world, x + dx, towerHeight + 2, z + radius, x + dx, towerHeight + 2, z + radius, STONE)
    end
    for dz = -radius, radius, 2 do
        Ops.fillBox(world, x - radius, towerHeight + 2, z + dz, x - radius, towerHeight + 2, z + dz, STONE)
        Ops.fillBox(world, x + radius, towerHeight + 2, z + dz, x + radius, towerHeight + 2, z + dz, STONE)
    end

    Ops.clearBox(world, x - 1, 2, z - radius, x + 1, 4, z - radius)
    Ops.clearBox(world, x - 1, wallHeight - 1, z - radius, x + 1, wallHeight + 1, z - radius)
end

local function addOuterWalls(world, left, right, front, back, wallHeight, thickness, gateHalfWidth)
    Ops.wallX(world, left, right, 2, wallHeight, front, thickness, STONE)
    Ops.wallX(world, left, right, 2, wallHeight, back, thickness, STONE)
    Ops.wallZ(world, left, 2, wallHeight, front, back, thickness, STONE)
    Ops.wallZ(world, right, 2, wallHeight, front, back, thickness, STONE)

    Ops.crenellateX(world, left, right, wallHeight + 1, front, STONE)
    Ops.crenellateX(world, left, right, wallHeight + 1, back, STONE)
    Ops.crenellateZ(world, left, wallHeight + 1, front, back, STONE)
    Ops.crenellateZ(world, right, wallHeight + 1, front, back, STONE)

    local gateX = math.floor((left + right) / 2)
    clearDoor(world, gateX - gateHalfWidth, front - 1, gateX + gateHalfWidth, front + 1, 5)
end

local function addGatehouse(world, gateX, front, wallHeight, towerRadius)
    local z = front + 3
    Ops.fillBox(world, gateX - 6, 2, z - 2, gateX + 6, wallHeight + 2, z + 3, STONE)
    clearDoor(world, gateX - 2, z - 2, gateX + 2, z + 3, 5)
    Ops.fillBox(world, gateX - 1, 6, z - 2, gateX + 1, wallHeight + 1, z + 3, WOOD)
    addTower(world, gateX - 7, z, towerRadius, wallHeight, wallHeight + 4)
    addTower(world, gateX + 7, z, towerRadius, wallHeight, wallHeight + 4)
end

local function addKeep(world, cx, cz, width, depth, height)
    local left = cx - math.floor(width / 2)
    local right = left + width
    local front = cz - math.floor(depth / 2)
    local back = front + depth

    Ops.hollowBox(world, left, 2, front, right, height, back, STONE)
    Ops.clearBox(world, cx - 2, 2, front, cx + 2, 5, front)
    Ops.clearBox(world, left + 2, height - 2, front, left + 3, height - 1, front)
    Ops.clearBox(world, right - 3, height - 2, back, right - 2, height - 1, back)
    Ops.crenellateX(world, left, right, height + 1, front, STONE)
    Ops.crenellateX(world, left, right, height + 1, back, STONE)
    Ops.crenellateZ(world, left, height + 1, front, back, STONE)
    Ops.crenellateZ(world, right, height + 1, front, back, STONE)
end

local function addCourtyard(world, gateX, front, cx, cz, left, right, back)
    Ops.fillBox(world, gateX - 2, 1, front + 1, gateX + 2, 1, cz, SAND)
    Ops.fillBox(world, cx - 2, 1, cz - 2, cx + 2, 1, cz + 2, SAND)
    Ops.fillBox(world, left + 6, 1, cz - 1, right - 6, 1, cz + 1, SAND)
    Ops.fillBox(world, cx - 1, 1, cz, cx + 1, 1, back - 5, SAND)
end

function CastleGenerator.generate(world, renderer, opts)
    opts = opts or {}
    local seed = opts.seed or os.time()
    math.randomseed(seed)

    resetWorld(world)

    local cx = opts.centerX or math.floor(world.width / 2)
    local cz = opts.centerZ or math.floor(world.depth / 2)
    local width = opts.width or choice(math.random, 38, 48)
    local depth = opts.depth or choice(math.random, 34, 46)
    local wallHeight = opts.wallHeight or choice(math.random, 8, 11)
    local towerHeight = opts.towerHeight or (wallHeight + choice(math.random, 4, 7))
    local towerRadius = opts.towerRadius or choice(math.random, 3, 4)
    local thickness = opts.wallThickness or 3

    width = clamp(width, 24, world.width - 16)
    depth = clamp(depth, 24, world.depth - 16)

    local left = clamp(cx - math.floor(width / 2), 8, world.width - width - 8)
    local right = left + width
    local front = clamp(cz - math.floor(depth / 2), 8, world.depth - depth - 8)
    local back = front + depth
    local gateX = math.floor((left + right) / 2)

    addOuterWalls(world, left, right, front, back, wallHeight, thickness, 2)
    addTower(world, left, front, towerRadius, wallHeight, towerHeight)
    addTower(world, right, front, towerRadius, wallHeight, towerHeight)
    addTower(world, left, back, towerRadius, wallHeight, towerHeight)
    addTower(world, right, back, towerRadius, wallHeight, towerHeight)
    addGatehouse(world, gateX, front, wallHeight, towerRadius)
    addKeep(world, cx, cz + choice(math.random, 2, 5), choice(math.random, 12, 16),
        choice(math.random, 10, 14), wallHeight + choice(math.random, 4, 7))
    addCourtyard(world, gateX, front, cx, cz, left, right, back)

    if renderer then
        renderer:markAllDirty()
        renderer:flushDirty()
    end

    return {
        seed = seed,
        left = left,
        right = right,
        front = front,
        back = back,
    }
end

return CastleGenerator
