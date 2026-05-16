-- ABOUTME: Per-operation undo / redo. Each op records (x,y,z,oldId,newId) for
-- ABOUTME: every cell it changed; Ctrl+Z reverses, Ctrl+Y / Ctrl+Shift+Z replays.
-- ABOUTME: Async stability cascades append to the triggering undo operation.

local UndoManager = {}
UndoManager.__index = UndoManager

local MAX_OPS = 30
local RLE_THRESHOLD = 2048

function UndoManager.new(world, renderer)
    return setmetatable({
        world = world,
        renderer = renderer,
        undoStack = {},
        redoStack = {},
        currentOp = nil,
        deferredOps = {},
    }, UndoManager)
end

function UndoManager:beginOp()
    self.currentOp = { kind = "cells", count = 0, data = {} }
    return self.currentOp
end

function UndoManager:recordChangeToOp(op, x, y, z, oldId, newId)
    if not op or oldId == newId then return end
    if op.kind ~= "cells" then return end
    local data = op.data
    local index = self.world:getIndex(x, y, z)
    data[#data + 1] = index
    data[#data + 1] = oldId
    data[#data + 1] = newId
    op.count = op.count + 1
end

function UndoManager:recordChange(x, y, z, oldId, newId)
    self:recordChangeToOp(self.currentOp, x, y, z, oldId, newId)
end

local function compactOp(op)
    if op.deferred then return op end
    if op.count <= RLE_THRESHOLD then return op end
    local source = op.data
    local entries = {}
    for i = 1, #source, 3 do
        entries[#entries + 1] = {
            index = source[i],
            oldId = source[i + 1],
            newId = source[i + 2],
        }
    end
    table.sort(entries, function(a, b) return a.index < b.index end)

    local runs = {}
    local runStart, runCount, runOld, runNew, prevIndex
    for i = 1, #entries do
        local e = entries[i]
        if runStart
            and e.index == prevIndex + 1
            and e.oldId == runOld
            and e.newId == runNew then
            runCount = runCount + 1
            prevIndex = e.index
        else
            if runStart then
                runs[#runs + 1] = runStart
                runs[#runs + 1] = runCount
                runs[#runs + 1] = runOld
                runs[#runs + 1] = runNew
            end
            runStart = e.index
            runCount = 1
            runOld = e.oldId
            runNew = e.newId
            prevIndex = e.index
        end
    end
    if runStart then
        runs[#runs + 1] = runStart
        runs[#runs + 1] = runCount
        runs[#runs + 1] = runOld
        runs[#runs + 1] = runNew
    end
    return { kind = "rle", count = op.count, runs = runs }
end

function UndoManager:endOp(deferCompact)
    local op = self.currentOp
    self.currentOp = nil
    if not op or op.count == 0 then return end
    if deferCompact then
        op.deferred = true
        self.deferredOps[op] = true
    end
    op = compactOp(op)
    self.undoStack[#self.undoStack + 1] = op
    while #self.undoStack > MAX_OPS do
        table.remove(self.undoStack, 1)
    end
    -- Any new edit invalidates the redo history.
    if #self.redoStack > 0 then
        for i = #self.redoStack, 1, -1 do self.redoStack[i] = nil end
    end
    return op
end

function UndoManager:finalizeOp(op)
    if not op or not op.deferred then return end
    op.deferred = nil
    self.deferredOps[op] = nil
    if op.count <= RLE_THRESHOLD then return end
    local compacted = compactOp(op)
    for i = 1, #self.undoStack do
        if self.undoStack[i] == op then
            self.undoStack[i] = compacted
            return
        end
    end
    for i = 1, #self.redoStack do
        if self.redoStack[i] == op then
            self.redoStack[i] = compacted
            return
        end
    end
end

function UndoManager:finalizeDeferredOps()
    for op in pairs(self.deferredOps) do
        self:finalizeOp(op)
    end
end

local function applyOpReverse(self, op)
    local world = self.world
    local renderer = self.renderer
    if op.kind == "rle" then
        for i = 1, #op.runs, 4 do
            local startIndex = op.runs[i]
            local count = op.runs[i + 1]
            local oldId = op.runs[i + 2]
            for offset = 0, count - 1 do
                local x, y, z = world:getXYZ(startIndex + offset)
                world:setBlock(x, y, z, oldId)
                renderer:markDirty(x, y, z)
            end
        end
    else
        local data = op.data
        for i = 1, #data, 3 do
            local x, y, z = world:getXYZ(data[i])
            world:setBlock(x, y, z, data[i + 1])
            renderer:markDirty(x, y, z)
        end
    end
    renderer:flushDirty()
end

local function applyOpForward(self, op)
    local world = self.world
    local renderer = self.renderer
    if op.kind == "rle" then
        for i = 1, #op.runs, 4 do
            local startIndex = op.runs[i]
            local count = op.runs[i + 1]
            local newId = op.runs[i + 3]
            for offset = 0, count - 1 do
                local x, y, z = world:getXYZ(startIndex + offset)
                world:setBlock(x, y, z, newId)
                renderer:markDirty(x, y, z)
            end
        end
    else
        local data = op.data
        for i = 1, #data, 3 do
            local x, y, z = world:getXYZ(data[i])
            world:setBlock(x, y, z, data[i + 2])
            renderer:markDirty(x, y, z)
        end
    end
    renderer:flushDirty()
end

function UndoManager:undo()
    local op = self.undoStack[#self.undoStack]
    if not op then return false end
    self:finalizeOp(op)
    op = self.undoStack[#self.undoStack]
    self.undoStack[#self.undoStack] = nil
    applyOpReverse(self, op)
    self.redoStack[#self.redoStack + 1] = op
    return true, op.count
end

function UndoManager:redo()
    local op = self.redoStack[#self.redoStack]
    if not op then return false end
    self:finalizeOp(op)
    op = self.redoStack[#self.redoStack]
    self.redoStack[#self.redoStack] = nil
    applyOpForward(self, op)
    self.undoStack[#self.undoStack + 1] = op
    return true, op.count
end

function UndoManager:clear()
    self.undoStack = {}
    self.redoStack = {}
    self.currentOp = nil
    self.deferredOps = {}
end

function UndoManager:stats()
    return #self.undoStack, #self.redoStack
end

return UndoManager
