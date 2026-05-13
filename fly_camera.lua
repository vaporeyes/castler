-- ABOUTME: First-person free-fly camera. Mouse-look (yaw + pitch), WASD strafe
-- ABOUTME: along the look direction, space/ctrl up-down, scroll adjusts speed.
-- ABOUTME: Used as an alternative to RTSCamera; both implement the same surface.

local Matrix = require("matrix")

local Fly = {}
Fly.__index = Fly

local PITCH_LIMIT = math.rad(89)
local MOUSE_SENS  = 0.003
local SHIFT_BOOST = 2.8

function Fly.new(opts)
    opts = opts or {}
    local self = setmetatable({}, Fly)
    self.pos   = opts.pos   or {0, 16, 0}
    self.yaw   = opts.yaw   or 0
    self.pitch = opts.pitch or 0
    -- 128-cell world feels right at ~2 seconds end-to-end; LShift gives a
    -- 2.8x boost for traversal. Wheel does NOT adjust speed in fly mode
    -- because trackpad gestures during mouse-look fire scroll events and
    -- would compound-decay the speed without the user noticing.
    self.speed = opts.speed or 60
    self.fov   = opts.fov   or math.rad(75)
    self.near  = opts.near  or 0.1
    self.far   = opts.far   or 2000
    self.active = false
    return self
end

-- Direction the camera is facing. yaw=0, pitch=0 looks toward -Z.
function Fly:forward()
    local cP = math.cos(self.pitch); local sP = math.sin(self.pitch)
    local cY = math.cos(self.yaw);   local sY = math.sin(self.yaw)
    return -sY * cP, sP, -cY * cP
end

function Fly:viewMatrix()
    local fx, fy, fz = self:forward()
    local target = { self.pos[1] + fx, self.pos[2] + fy, self.pos[3] + fz }
    return Matrix.lookAt(self.pos, target, {0, 1, 0})
end

function Fly:projectionMatrix(aspect)
    return Matrix.perspective(self.fov, aspect, self.near, self.far)
end

function Fly:eye()
    return { self.pos[1], self.pos[2], self.pos[3] }
end

function Fly:update(dt)
    if not self.active or not love.keyboard then return end

    local fx, fy, fz = self:forward()
    -- Horizontal-only right vector so A/D strafe stays level even when looking
    -- up or down. Yaw=0 forward = -Z, so right at yaw=0 = +X.
    local rx = math.cos(self.yaw)
    local rz = -math.sin(self.yaw)

    local speed = self.speed * dt
    if love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift") then
        speed = speed * SHIFT_BOOST
    end

    local mx, my, mz = 0, 0, 0
    if love.keyboard.isDown("w") then mx = mx + fx; my = my + fy; mz = mz + fz end
    if love.keyboard.isDown("s") then mx = mx - fx; my = my - fy; mz = mz - fz end
    if love.keyboard.isDown("d") then mx = mx + rx;               mz = mz + rz end
    if love.keyboard.isDown("a") then mx = mx - rx;               mz = mz - rz end
    if love.keyboard.isDown("space")                              then my = my + 1 end
    if love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl") then my = my - 1 end

    self.pos[1] = self.pos[1] + mx * speed
    self.pos[2] = self.pos[2] + my * speed
    self.pos[3] = self.pos[3] + mz * speed
end

function Fly:mousemoved(_, _, dx, dy)
    if not self.active then return end
    self.yaw   = self.yaw   - dx * MOUSE_SENS
    self.pitch = self.pitch - dy * MOUSE_SENS
    if self.pitch >  PITCH_LIMIT then self.pitch =  PITCH_LIMIT end
    if self.pitch < -PITCH_LIMIT then self.pitch = -PITCH_LIMIT end
end

function Fly:wheelmoved(_, _)
    -- Intentionally no-op in fly mode. Trackpad two-finger gestures during
    -- mouse-look generate spurious scroll events; mapping them to speed leads
    -- to gradual unintended slowdowns. Use LShift for a boost instead.
end

function Fly:mousepressed() end
function Fly:mousereleased() end

-- Start the fly camera from wherever the RTS camera is currently looking, so
-- toggling feels continuous.
function Fly:syncFromRTS(rts)
    local eye = rts:eye()
    self.pos = { eye[1], eye[2], eye[3] }
    -- Convert RTS yaw/pitch (target-relative orbit) to look-from-eye angles.
    -- See doc comment in main.lua for the derivation.
    self.yaw   = rts.cYaw
    self.pitch = -rts.cPitch
end

function Fly:activate()
    self.active = true
    if love.mouse and love.mouse.setRelativeMode then
        love.mouse.setRelativeMode(true)
    end
end

function Fly:deactivate()
    self.active = false
    if love.mouse and love.mouse.setRelativeMode then
        love.mouse.setRelativeMode(false)
    end
end

return Fly
