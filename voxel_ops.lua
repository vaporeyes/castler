-- ABOUTME: Reusable voxel stamping primitives for generated structures.
-- ABOUTME: Provides boxes, hollow boxes, cylinders, walls, and crenellations.

local VoxelOps = {}

local function ordered(a, b)
    if a <= b then return a, b end
    return b, a
end

local function setIfInBounds(world, x, y, z, id)
    if world:inBounds(x, y, z) then
        world:setBlock(x, y, z, id)
    end
end

function VoxelOps.fillBox(world, x1, y1, z1, x2, y2, z2, id)
    local xLo, xHi = ordered(x1, x2)
    local yLo, yHi = ordered(y1, y2)
    local zLo, zHi = ordered(z1, z2)
    for z = zLo, zHi do
        for y = yLo, yHi do
            for x = xLo, xHi do
                setIfInBounds(world, x, y, z, id)
            end
        end
    end
end

function VoxelOps.hollowBox(world, x1, y1, z1, x2, y2, z2, id)
    local xLo, xHi = ordered(x1, x2)
    local yLo, yHi = ordered(y1, y2)
    local zLo, zHi = ordered(z1, z2)
    for z = zLo, zHi do
        for y = yLo, yHi do
            for x = xLo, xHi do
                if x == xLo or x == xHi
                or y == yLo or y == yHi
                or z == zLo or z == zHi then
                    setIfInBounds(world, x, y, z, id)
                end
            end
        end
    end
end

function VoxelOps.clearBox(world, x1, y1, z1, x2, y2, z2)
    VoxelOps.fillBox(world, x1, y1, z1, x2, y2, z2, 0)
end

function VoxelOps.cylinder(world, cx, cz, radius, y1, y2, id, hollow)
    local yLo, yHi = ordered(y1, y2)
    local r2 = radius * radius
    local inner = math.max(0, radius - 1)
    local inner2 = inner * inner
    for z = cz - radius, cz + radius do
        for x = cx - radius, cx + radius do
            local dx = x - cx
            local dz = z - cz
            local d2 = dx * dx + dz * dz
            if d2 <= r2 and (not hollow or d2 >= inner2) then
                for y = yLo, yHi do
                    setIfInBounds(world, x, y, z, id)
                end
            end
        end
    end
end

function VoxelOps.wallX(world, x1, x2, y1, y2, z, thickness, id)
    local half = math.floor((thickness or 1) / 2)
    VoxelOps.fillBox(world, x1, y1, z - half, x2, y2, z + half, id)
end

function VoxelOps.wallZ(world, x, y1, y2, z1, z2, thickness, id)
    local half = math.floor((thickness or 1) / 2)
    VoxelOps.fillBox(world, x - half, y1, z1, x + half, y2, z2, id)
end

function VoxelOps.crenellateX(world, x1, x2, y, z, id)
    local xLo, xHi = ordered(x1, x2)
    for x = xLo, xHi, 2 do
        setIfInBounds(world, x, y, z, id)
    end
end

function VoxelOps.crenellateZ(world, x, y, z1, z2, id)
    local zLo, zHi = ordered(z1, z2)
    for z = zLo, zHi, 2 do
        setIfInBounds(world, x, y, z, id)
    end
end

function VoxelOps.floor(world, id)
    for z = 1, world.depth do
        for x = 1, world.width do
            world:setBlock(x, 1, z, id)
        end
    end
end

return VoxelOps
