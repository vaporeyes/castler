-- ABOUTME: First-person camera with two modes - noclip free-fly and a walk
-- ABOUTME: mode with gravity, AABB-vs-voxel collision, wall sliding, step-up,
-- ABOUTME: and jumping. Shares the RTSCamera surface (viewMatrix etc).

local Matrix = require("matrix")

local Fly = {}
Fly.__index = Fly

local PITCH_LIMIT = math.rad(89)
local MOUSE_SENS  = 0.003
local SHIFT_BOOST = 2.8     -- noclip sprint multiplier

-- Walk-mode tuning. Units are voxel cells. Block (bx,by,bz) occupies world
-- cube [bx-1,bx] x [by-1,by] x [bz-1,bz], so a cell index for world coord c
-- is floor(c)+1 and a block's top surface sits at world y == by.
local EYE_HEIGHT  = 1.6
local BODY_HEIGHT = 1.8
local BODY_HALF   = 0.3
local STEP_HEIGHT = 1.05    -- max ledge auto-climbed (1 voxel + slack)
local GRAVITY     = 22
local TERMINAL    = 45
local JUMP_SPEED  = 8
local WALK_SPEED  = 14
local WALK_RUN    = 1.9     -- LShift multiplier on foot
local MAX_SUBSTEP = 0.4     -- cap per-substep travel so we never tunnel
local EPS         = 1e-4

function Fly.new(opts)
    opts = opts or {}
    local self = setmetatable({}, Fly)
    self.world = opts.world
    self.pos   = opts.pos   or {0, 16, 0}
    self.yaw   = opts.yaw   or 0
    self.pitch = opts.pitch or 0
    self.speed = opts.speed or 60      -- noclip speed
    self.fov   = opts.fov   or math.rad(75)
    self.near  = opts.near  or 0.1
    self.far   = opts.far   or 2000
    self.active = false
    self.collide = false               -- false = noclip fly, true = walk
    self.vy = 0
    self.onGround = false
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

-- True if the player AABB centered at eye (ex,ey,ez) overlaps any solid cell.
-- Out-of-world reads return air (VoxelWorld:getBlock), so the map edge is a
-- ledge you can walk off, not an invisible wall.
local function bodyCollides(world, ex, ey, ez)
    if not world then return false end
    local feet = ey - EYE_HEIGHT
    local bx0 = math.floor(ex - BODY_HALF + EPS) + 1
    local bx1 = math.floor(ex + BODY_HALF - EPS) + 1
    local by0 = math.floor(feet + EPS) + 1
    local by1 = math.floor(feet + BODY_HEIGHT - EPS) + 1
    local bz0 = math.floor(ez - BODY_HALF + EPS) + 1
    local bz1 = math.floor(ez + BODY_HALF - EPS) + 1
    for bz = bz0, bz1 do
        for by = by0, by1 do
            for bx = bx0, bx1 do
                if world:getBlock(bx, by, bz) ~= 0 then
                    return true
                end
            end
        end
    end
    return false
end

-- Drop the eye so the feet rest on the highest solid block in the current
-- column. Called when entering walk mode / spawning so we don't start the
-- frame embedded in geometry.
function Fly:settleToGround()
    local world = self.world
    if not world then return end
    local cx = math.floor(self.pos[1]) + 1
    local cz = math.floor(self.pos[3]) + 1
    for by = world.height, 1, -1 do
        if world:getBlock(cx, by, cz) ~= 0 then
            self.pos[2] = by + EYE_HEIGHT  -- block top surface is at world y == by
            self.vy = 0
            self.onGround = true
            return
        end
    end
end

function Fly:setCollide(on)
    self.collide = on and true or false
    if self.collide then
        self.vy = 0
        -- Clamp into world bounds first so a panned/orbited camera can't drop
        -- the player off the grass floor into a permanent fall. The floor at
        -- y=1 spans the whole map, so an in-bounds column always has ground.
        local world = self.world
        if world then
            self.pos[1] = math.max(0.5, math.min(world.width - 0.5, self.pos[1]))
            self.pos[3] = math.max(0.5, math.min(world.depth - 0.5, self.pos[3]))
        end
        self:settleToGround()
    end
end

function Fly:modeName()
    return self.collide and "walk" or "noclip"
end

-- Noclip: free 6-DOF movement, no gravity, no collision (original behavior).
local function updateNoclip(self, dt)
    local fx, fy, fz = self:forward()
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

-- Walk: gravity + axis-separated voxel collision with wall sliding, plus a
-- step-up so 1-voxel ledges (castle steps, DOOM thresholds) are climbable.
local function updateWalk(self, dt)
    local world = self.world

    -- Horizontal wish velocity from yaw-only basis (look up/down doesn't fly).
    local fwdX, fwdZ = -math.sin(self.yaw), -math.cos(self.yaw)
    local rgtX, rgtZ =  math.cos(self.yaw), -math.sin(self.yaw)
    local wx, wz = 0, 0
    if love.keyboard.isDown("w") then wx = wx + fwdX; wz = wz + fwdZ end
    if love.keyboard.isDown("s") then wx = wx - fwdX; wz = wz - fwdZ end
    if love.keyboard.isDown("d") then wx = wx + rgtX; wz = wz + rgtZ end
    if love.keyboard.isDown("a") then wx = wx - rgtX; wz = wz - rgtZ end
    local len = math.sqrt(wx * wx + wz * wz)
    local speed = WALK_SPEED
    if love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift") then
        speed = speed * WALK_RUN
    end
    if len > 0 then
        wx, wz = wx / len * speed, wz / len * speed
    end

    -- Gravity + jump.
    self.vy = self.vy - GRAVITY * dt
    if self.vy < -TERMINAL then self.vy = -TERMINAL end
    if self.onGround and love.keyboard.isDown("space") then
        self.vy = JUMP_SPEED
        self.onGround = false
    end

    local dx = wx * dt
    local dy = self.vy * dt
    local dz = wz * dt

    -- Sub-step so a single fast frame can't tunnel through a wall.
    local biggest = math.max(math.abs(dx), math.abs(dy), math.abs(dz))
    local steps = math.max(1, math.ceil(biggest / MAX_SUBSTEP))
    local sx, sy, sz = dx / steps, dy / steps, dz / steps

    for _ = 1, steps do
        -- Vertical.
        self.pos[2] = self.pos[2] + sy
        if bodyCollides(world, self.pos[1], self.pos[2], self.pos[3]) then
            self.pos[2] = self.pos[2] - sy
            if sy < 0 then self.onGround = true end
            self.vy = 0
        end

        -- X axis with step-up.
        self.pos[1] = self.pos[1] + sx
        if bodyCollides(world, self.pos[1], self.pos[2], self.pos[3]) then
            self.pos[2] = self.pos[2] + STEP_HEIGHT
            if bodyCollides(world, self.pos[1], self.pos[2], self.pos[3]) then
                self.pos[2] = self.pos[2] - STEP_HEIGHT
                self.pos[1] = self.pos[1] - sx
            else
                self.vy = 0
            end
        end

        -- Z axis with step-up.
        self.pos[3] = self.pos[3] + sz
        if bodyCollides(world, self.pos[1], self.pos[2], self.pos[3]) then
            self.pos[2] = self.pos[2] + STEP_HEIGHT
            if bodyCollides(world, self.pos[1], self.pos[2], self.pos[3]) then
                self.pos[2] = self.pos[2] - STEP_HEIGHT
                self.pos[3] = self.pos[3] - sz
            else
                self.vy = 0
            end
        end
    end

    -- Re-evaluate grounding by probing just below the feet so jump stays
    -- reliable and walking off a ledge clears onGround immediately.
    self.onGround = bodyCollides(world, self.pos[1], self.pos[2] - 0.06, self.pos[3])
    if self.onGround and self.vy < 0 then self.vy = 0 end

    -- Soft kill floor: never fall below the world bottom into infinity.
    if self.pos[2] - EYE_HEIGHT < 0 then
        self.pos[2] = EYE_HEIGHT
        self.vy = 0
        self.onGround = true
    end
end

function Fly:update(dt)
    if not self.active or not love.keyboard then return end
    if self.collide and self.world then
        updateWalk(self, dt)
    else
        updateNoclip(self, dt)
    end
end

function Fly:mousemoved(_, _, dx, dy)
    if not self.active then return end
    self.yaw   = self.yaw   - dx * MOUSE_SENS
    self.pitch = self.pitch - dy * MOUSE_SENS
    if self.pitch >  PITCH_LIMIT then self.pitch =  PITCH_LIMIT end
    if self.pitch < -PITCH_LIMIT then self.pitch = -PITCH_LIMIT end
end

function Fly:wheelmoved(_, _)
    -- Intentionally no-op. Trackpad two-finger gestures during mouse-look
    -- generate spurious scroll events; mapping them to speed leads to gradual
    -- unintended slowdowns. Use LShift for a boost instead.
end

function Fly:mousepressed() end
function Fly:mousereleased() end

-- Start the fly camera from wherever the RTS camera is currently looking, so
-- toggling feels continuous.
function Fly:syncFromRTS(rts)
    local eye = rts:eye()
    self.pos = { eye[1], eye[2], eye[3] }
    self.yaw   = rts.cYaw
    self.pitch = -rts.cPitch
    self.vy = 0
    if self.collide then self:settleToGround() end
end

function Fly:activate()
    self.active = true
    self.vy = 0
    if self.collide then self:settleToGround() end
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
