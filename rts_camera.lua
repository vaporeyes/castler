-- ABOUTME: RTS-style orbit camera. Spherical coords (yaw, pitch, distance) around
-- ABOUTME: a target point on the ground. WASD pans, scroll zooms, RMB drag rotates.

local Matrix = require("matrix")

local RTSCamera = {}
RTSCamera.__index = RTSCamera

local PITCH_MIN = math.rad(10)
local PITCH_MAX = math.rad(85)
local DIST_MIN = 6
local DIST_MAX = 400
local PAN_SPEED = 22       -- world units / second
local ROT_SENSITIVITY = 0.006
local ZOOM_STEP = 0.88     -- multiplier per wheel notch
local SMOOTH_RATE = 14     -- larger = snappier

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function RTSCamera.new(opts)
    opts = opts or {}
    local self = setmetatable({}, RTSCamera)

    -- Target values (what we're animating toward).
    self.targetPos = opts.target or {16, 0, 16}
    self.yaw      = opts.yaw      or math.rad(35)
    self.pitch    = opts.pitch    or math.rad(55)
    self.distance = opts.distance or 38

    -- Smoothed display values (what we actually render with).
    self.cTarget   = {self.targetPos[1], self.targetPos[2], self.targetPos[3]}
    self.cYaw      = self.yaw
    self.cPitch    = self.pitch
    self.cDistance = self.distance

    self.fov  = opts.fov  or math.rad(60)
    self.near = opts.near or 0.1
    self.far  = opts.far  or 2000

    self.rotating = false

    return self
end

-- Direction unit vector from target -> eye, based on current smoothed yaw/pitch.
function RTSCamera:eyeOffsetDir()
    local cp = math.cos(self.cPitch)
    local sp = math.sin(self.cPitch)
    local cy = math.cos(self.cYaw)
    local sy = math.sin(self.cYaw)
    return cp * sy, sp, cp * cy
end

function RTSCamera:eye()
    local dx, dy, dz = self:eyeOffsetDir()
    return {
        self.cTarget[1] + dx * self.cDistance,
        self.cTarget[2] + dy * self.cDistance,
        self.cTarget[3] + dz * self.cDistance,
    }
end

function RTSCamera:viewMatrix()
    return Matrix.lookAt(self:eye(), self.cTarget, {0, 1, 0})
end

function RTSCamera:projectionMatrix(aspect)
    return Matrix.perspective(self.fov, aspect, self.near, self.far)
end

function RTSCamera:update(dt)
    -- WASD pan: forward is camera's look direction projected onto XZ.
    if not love.keyboard then return end

    local fx, _, fz = self:eyeOffsetDir()
    -- Forward (toward target) is the negative of the offset direction.
    local forwardX, forwardZ = -fx, -fz
    local fLen = math.sqrt(forwardX * forwardX + forwardZ * forwardZ)
    if fLen > 1e-6 then
        forwardX = forwardX / fLen
        forwardZ = forwardZ / fLen
    end
    -- Right vector = forward x up (right-handed, up = +Y).
    local rightX = -forwardZ
    local rightZ = forwardX

    local mx, mz = 0, 0
    if love.keyboard.isDown("w") then mx = mx + forwardX; mz = mz + forwardZ end
    if love.keyboard.isDown("s") then mx = mx - forwardX; mz = mz - forwardZ end
    if love.keyboard.isDown("d") then mx = mx + rightX;   mz = mz + rightZ end
    if love.keyboard.isDown("a") then mx = mx - rightX;   mz = mz - rightZ end

    if mx ~= 0 or mz ~= 0 then
        -- Scale pan speed with distance so it feels consistent while zoomed out.
        local speed = PAN_SPEED * dt * (self.cDistance / 38)
        self.targetPos[1] = self.targetPos[1] + mx * speed
        self.targetPos[3] = self.targetPos[3] + mz * speed
    end

    -- Exponential smoothing toward target values.
    local t = 1 - math.exp(-SMOOTH_RATE * dt)
    self.cTarget[1] = lerp(self.cTarget[1], self.targetPos[1], t)
    self.cTarget[2] = lerp(self.cTarget[2], self.targetPos[2], t)
    self.cTarget[3] = lerp(self.cTarget[3], self.targetPos[3], t)
    self.cYaw       = lerp(self.cYaw,      self.yaw,      t)
    self.cPitch     = lerp(self.cPitch,    self.pitch,    t)
    self.cDistance  = lerp(self.cDistance, self.distance, t)
end

local function altHeld()
    return love.keyboard.isDown("lalt") or love.keyboard.isDown("ralt")
end

-- Orbit is now Alt + left-drag (RMB is reserved for block removal). Holding
-- Alt when pressing LMB starts an orbit; releasing LMB ends it.
function RTSCamera:mousepressed(x, y, button)
    if button == 1 and altHeld() then self.rotating = true end
end

function RTSCamera:mousereleased(x, y, button)
    if button == 1 then self.rotating = false end
end

function RTSCamera:mousemoved(x, y, dx, dy)
    if self.rotating then
        self.yaw = self.yaw - dx * ROT_SENSITIVITY
        self.pitch = clamp(self.pitch + dy * ROT_SENSITIVITY, PITCH_MIN, PITCH_MAX)
    end
end

function RTSCamera:wheelmoved(x, y)
    if y == 0 then return end
    local factor = (y > 0) and (ZOOM_STEP ^ y) or ((1 / ZOOM_STEP) ^ (-y))
    self.distance = clamp(self.distance * factor, DIST_MIN, DIST_MAX)
end

return RTSCamera
