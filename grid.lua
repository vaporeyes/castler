-- ABOUTME: Optional reference grid drawn on the floor plane. Built as a 3D mesh
-- ABOUTME: of thin quads so the GPU handles near-plane clipping naturally and so
-- ABOUTME: we can opt into depth-tested occlusion behind voxels.

local Grid = {}
Grid.__index = Grid

local MODE_OFF      = 0
local MODE_OVERLAY  = 1
local MODE_OCCLUDED = 2

local VERTEX_FORMAT = {
    {"VertexPosition", "float", 3},
    {"VertexColor",    "float", 4},
}

local function loadShader()
    return love.graphics.newShader(love.filesystem.read("shaders/voxel.glsl"))
end

function Grid.new(world, camera, chunkSize)
    local self = setmetatable({
        world = world,
        camera = camera,
        chunkSize = chunkSize or 16,
        mode = MODE_OFF,
    }, Grid)
    self.shader = loadShader()
    self:buildMesh()
    return self
end

function Grid:cycle()
    self.mode = (self.mode + 1) % 3
end

function Grid:isVisible() return self.mode ~= MODE_OFF end

function Grid:modeName()
    if self.mode == MODE_OFF then return "off"
    elseif self.mode == MODE_OVERLAY then return "overlay"
    else return "occluded" end
end

function Grid:buildMesh()
    local w, d = self.world.width, self.world.depth
    local step = self.chunkSize
    -- Just above the floor so depth-tested rendering doesn't z-fight with it.
    local y = 1.01

    -- Half-thicknesses in world units (line "width").
    local minorT = 0.025
    local majorT = 0.05

    -- Minor lines (between chunk boundaries) - subtle white.
    local minorR, minorG, minorB, minorA = 1, 1, 1, 0.22
    -- Major lines (chunk boundaries) - cyan, more prominent.
    local majorR, majorG, majorB, majorA = 0.55, 0.85, 1, 0.75

    local verts = {}
    local indices = {}

    local function addQuad(x1, z1, x2, z2, r, g, b, a)
        local base = #verts
        verts[#verts + 1] = {x1, y, z1, r, g, b, a}
        verts[#verts + 1] = {x2, y, z1, r, g, b, a}
        verts[#verts + 1] = {x2, y, z2, r, g, b, a}
        verts[#verts + 1] = {x1, y, z2, r, g, b, a}
        indices[#indices + 1] = base + 1
        indices[#indices + 1] = base + 2
        indices[#indices + 1] = base + 3
        indices[#indices + 1] = base + 1
        indices[#indices + 1] = base + 3
        indices[#indices + 1] = base + 4
    end

    -- Lines parallel to the Z axis (constant X): span z=[0..d], thin in X.
    for x = 0, w do
        if x % step == 0 then
            addQuad(x - majorT, 0, x + majorT, d, majorR, majorG, majorB, majorA)
        else
            addQuad(x - minorT, 0, x + minorT, d, minorR, minorG, minorB, minorA)
        end
    end
    -- Lines parallel to the X axis (constant Z): span x=[0..w], thin in Z.
    for z = 0, d do
        if z % step == 0 then
            addQuad(0, z - majorT, w, z + majorT, majorR, majorG, majorB, majorA)
        else
            addQuad(0, z - minorT, w, z + minorT, minorR, minorG, minorB, minorA)
        end
    end

    self.mesh = love.graphics.newMesh(VERTEX_FORMAT, verts, "triangles", "static")
    self.mesh:setVertexMap(indices)
end

function Grid:draw()
    if self.mode == MODE_OFF then return end

    local sw, sh = love.graphics.getDimensions()
    local view = self.camera:viewMatrix()
    local proj = self.camera:projectionMatrix(sw / sh)

    love.graphics.push("all")
    if self.mode == MODE_OCCLUDED then
        -- Depth test enabled, depth WRITE disabled so the translucent grid
        -- doesn't pollute the depth buffer for things drawn afterward.
        love.graphics.setDepthMode("less", false)
    else
        love.graphics.setDepthMode()
    end
    love.graphics.setShader(self.shader)
    self.shader:send("u_view", "column", view)
    self.shader:send("u_proj", "column", proj)
    love.graphics.draw(self.mesh)
    love.graphics.pop()
end

return Grid
