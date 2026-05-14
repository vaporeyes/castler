-- ABOUTME: Per-operation undo / redo. Each op records (x,y,z,oldId,newId) for
-- ABOUTME: every cell it changed; Ctrl+Z reverses, Ctrl+Y / Ctrl+Shift+Z replays.
-- ABOUTME: Stability cascades join the triggering op so a single undo restores
-- ABOUTME: both the click and the dominoes it knocked over.

local UndoManager = {}
UndoManager.__index = UndoManager

local MAX_OPS = 30

function UndoManager.new(world, renderer)
    return setmetatable({
        world = world,
        renderer = renderer,
        undoStack = {},
        redoStack = {},
        currentOp = nil,
    }, UndoManager)
end

function UndoManager:beginOp()
    self.currentOp = {}
end

function UndoManager:recordChange(x, y, z, oldId, newId)
    local op = self.currentOp
    if not op or oldId == newId then return end
    op[#op + 1] = x
    op[#op + 1] = y
    op[#op + 1] = z
    op[#op + 1] = oldId
    op[#op + 1] = newId
end

function UndoManager:endOp()
    local op = self.currentOp
    self.currentOp = nil
    if not op or #op == 0 then return end
    self.undoStack[#self.undoStack + 1] = op
    while #self.undoStack > MAX_OPS do
        table.remove(self.undoStack, 1)
    end
    -- Any new edit invalidates the redo history.
    if #self.redoStack > 0 then
        for i = #self.redoStack, 1, -1 do self.redoStack[i] = nil end
    end
end

local function applyOpReverse(self, op)
    local world = self.world
    local renderer = self.renderer
    for i = 1, #op, 5 do
        world:setBlock(op[i], op[i + 1], op[i + 2], op[i + 3])
        renderer:markDirty(op[i], op[i + 1], op[i + 2])
    end
    renderer:flushDirty()
end

local function applyOpForward(self, op)
    local world = self.world
    local renderer = self.renderer
    for i = 1, #op, 5 do
        world:setBlock(op[i], op[i + 1], op[i + 2], op[i + 4])
        renderer:markDirty(op[i], op[i + 1], op[i + 2])
    end
    renderer:flushDirty()
end

function UndoManager:undo()
    local op = self.undoStack[#self.undoStack]
    if not op then return false end
    self.undoStack[#self.undoStack] = nil
    applyOpReverse(self, op)
    self.redoStack[#self.redoStack + 1] = op
    return true, #op / 5
end

function UndoManager:redo()
    local op = self.redoStack[#self.redoStack]
    if not op then return false end
    self.redoStack[#self.redoStack] = nil
    applyOpForward(self, op)
    self.undoStack[#self.undoStack + 1] = op
    return true, #op / 5
end

function UndoManager:clear()
    self.undoStack = {}
    self.redoStack = {}
    self.currentOp = nil
end

function UndoManager:stats()
    return #self.undoStack, #self.redoStack
end

return UndoManager
