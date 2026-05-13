-- ABOUTME: Lightweight 3D-positioned particles drawn as 2D screen-space quads.
-- ABOUTME: Spawned when blocks collapse from a stability cascade; integrate via
-- ABOUTME: gravity, project to screen each frame, fade out and despawn.

local Matrix = require("matrix")

local Particles = {}
Particles.__index = Particles

local LIFETIME = 1.4    -- seconds
local GRAVITY  = 22     -- world units / s^2 (positive = pulls -Y)
local PER_BLOCK = 5

function Particles.new()
    local self = setmetatable({}, Particles)
    self.list = {}
    return self
end

function Particles:spawnBlock(x, y, z, color)
    -- Block (x,y,z) occupies world cube [x-1..x, y-1..y, z-1..z]; center at -0.5.
    local cx, cy, cz = x - 0.5, y - 0.5, z - 0.5
    local r = color[1] or 1
    local g = color[2] or 1
    local b = color[3] or 1
    for _ = 1, PER_BLOCK do
        self.list[#self.list + 1] = {
            x  = cx + (math.random() - 0.5) * 0.6,
            y  = cy + (math.random() - 0.5) * 0.6,
            z  = cz + (math.random() - 0.5) * 0.6,
            vx = (math.random() - 0.5) * 3,
            vy = math.random() * 3 + 1,
            vz = (math.random() - 0.5) * 3,
            r = r, g = g, b = b,
            life = LIFETIME,
        }
    end
end

function Particles:update(dt)
    local list = self.list
    local write = 1
    for i = 1, #list do
        local p = list[i]
        p.life = p.life - dt
        if p.life > 0 then
            p.vy = p.vy - GRAVITY * dt
            p.x = p.x + p.vx * dt
            p.y = p.y + p.vy * dt
            p.z = p.z + p.vz * dt
            if write ~= i then list[write] = p end
            write = write + 1
        end
    end
    for i = write, #list do list[i] = nil end
end

function Particles:draw(view, proj)
    local list = self.list
    if #list == 0 then return end

    local sw, sh = love.graphics.getDimensions()
    local mvp = Matrix.mul(proj, view)

    love.graphics.push("all")
    love.graphics.setDepthMode()
    for i = 1, #list do
        local p = list[i]
        local cx, cy, _, cw = Matrix.mulVec4(mvp, p.x, p.y, p.z, 1)
        if cw > 0 then
            local nx = cx / cw
            local ny = cy / cw
            local sx = (nx * 0.5 + 0.5) * sw
            local sy = (1 - (ny * 0.5 + 0.5)) * sh

            -- Size shrinks with distance (cw == -z_view in OpenGL convention).
            local size = math.max(2, math.min(8, 50 / cw))
            local alpha = math.min(1, p.life / 0.5)
            love.graphics.setColor(p.r, p.g, p.b, alpha)
            love.graphics.rectangle("fill", sx - size * 0.5, sy - size * 0.5, size, size)
        end
    end
    love.graphics.pop()
end

function Particles:count() return #self.list end

return Particles
