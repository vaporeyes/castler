-- ABOUTME: Lightweight Lua smoke tests for renderer, undo, and stability paths.
-- ABOUTME: Runs without Love2D by stubbing the small graphics/timer surface used.

package.path = "./?.lua;../?.lua;" .. package.path

love = {
    filesystem = {
        read = function() return "" end,
    },
    graphics = {
        newShader = function()
            return {send = function() end}
        end,
        newMesh = function()
            return {
                setVertices = function() end,
                setVertexMap = function() end,
                setDrawRange = function() end,
            }
        end,
    },
}

local function assertEq(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)), 2)
    end
end

local function assertTrue(value, label)
    if not value then error(label, 2) end
end

local VoxelWorld = require("voxel_world")
local ChunkManager = require("chunk_manager")
local UndoManager = require("undo_manager")
local Stability = require("structural_integrity")

local function testFlatFloorGreedyMesh()
    local world = VoxelWorld.new(16, 4, 16)
    local renderer = ChunkManager.new(world)
    local verts, tris, drawn, total = renderer:getStats()
    assertEq(verts, 24, "flat floor vertex count")
    assertEq(tris, 12, "flat floor triangle count")
    assertEq(drawn, 1, "flat floor drawn chunks")
    assertEq(total, 1, "flat floor total chunks")
end

local function testAoAwareSplit()
    local world = VoxelWorld.new(16, 8, 16)
    for y = 2, 5 do
        world:setBlock(8, y, 8, 1)
    end
    local renderer = ChunkManager.new(world)
    local verts = renderer:getStats()
    assertTrue(verts > 24, "pillar should split some floor quads for AO")
    assertTrue(verts < 256, "pillar case should still be greedily meshed")
end

local function testRleUndo()
    local world = VoxelWorld.new(64, 8, 64)
    local renderer = {
        markDirty = function() end,
        flushDirty = function() end,
    }
    local undo = UndoManager.new(world, renderer)
    undo:beginOp()
    for i = 1, 3000 do
        local x = ((i - 1) % 64) + 1
        local z = (math.floor((i - 1) / 64) % 64) + 1
        undo:recordChange(x, 2, z, 0, 1)
        world:setBlock(x, 2, z, 1)
    end
    undo:endOp()
    assertEq(undo.undoStack[1].kind, "rle", "large undo operation kind")
    local ok, count = undo:undo()
    assertTrue(ok, "large undo should succeed")
    assertEq(count, 3000, "large undo count")
    assertEq(world:getBlock(1, 2, 1), 0, "large undo block state")
end

local function testAsyncStabilityUndoGrouping()
    local now = 0
    love.timer = {
        getTime = function()
            now = now + 0.0001
            return now
        end,
    }

    local world = VoxelWorld.new(8, 8, 8)
    world:setBlock(4, 2, 4, 1)
    world:setBlock(4, 3, 4, 1)
    local renderer = {
        markDirty = function() end,
        flushDirty = function() end,
    }
    local undo = UndoManager.new(world, renderer)
    local stability = Stability.new(world)

    local op = undo:beginOp()
    undo:recordChange(4, 2, 4, 1, 0)
    world:setBlock(4, 2, 4, 0)
    stability:enqueueCheck(4, 2, 4, op)
    undo:endOp(true)

    while stability:hasPending() do
        stability:update(0.002, function(x, y, z, oldId, undoOp)
            undo:recordChangeToOp(undoOp, x, y, z, oldId, 0)
        end)
    end
    undo:finalizeDeferredOps()

    local ok, count = undo:undo()
    assertTrue(ok, "grouped stability undo should succeed")
    assertEq(count, 2, "grouped stability undo count")
    assertEq(world:getBlock(4, 2, 4), 1, "removed support restored")
    assertEq(world:getBlock(4, 3, 4), 1, "collapsed block restored")
end

testFlatFloorGreedyMesh()
testAoAwareSplit()
testRleUndo()
testAsyncStabilityUndoGrouping()

print("smoke tests passed")
