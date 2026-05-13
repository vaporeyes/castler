-- ABOUTME: Minimal DOOM WAD parser. Reads the header, lump directory, and the
-- ABOUTME: four lumps we need to voxelize a level: VERTEXES, LINEDEFS,
-- ABOUTME: SIDEDEFS, SECTORS. Handles vanilla DOOM (not Hexen) linedef format.

local bit = require("bit")

local Wad = {}

local function u8(data, pos)
    return data:byte(pos), pos + 1
end

local function u16(data, pos)
    return bit.bor(data:byte(pos), bit.lshift(data:byte(pos + 1), 8)), pos + 2
end

local function s16(data, pos)
    local v, p = u16(data, pos)
    if v >= 0x8000 then v = v - 0x10000 end
    return v, p
end

local function u32(data, pos)
    local b1 = data:byte(pos)
    local b2 = data:byte(pos + 1)
    local b3 = data:byte(pos + 2)
    local b4 = data:byte(pos + 3)
    return bit.bor(
        bit.bor(b1, bit.lshift(b2, 8)),
        bit.bor(bit.lshift(b3, 16), bit.lshift(b4, 24))
    ), pos + 4
end

local function name8(data, pos)
    local raw = data:sub(pos, pos + 7)
    local zero = raw:find("\0", 1, true)
    local s = zero and raw:sub(1, zero - 1) or raw
    return s:upper(), pos + 8
end

local function readHeader(data)
    if #data < 12 then return nil, "file too short for WAD header" end
    local magic = data:sub(1, 4)
    if magic ~= "IWAD" and magic ~= "PWAD" then
        return nil, "not a WAD file (magic=" .. magic .. ")"
    end
    local numLumps, p = u32(data, 5)
    local dirOffset = u32(data, 9)
    return { magic = magic, numLumps = numLumps, dirOffset = dirOffset }
end

local function readDirectory(data, header)
    local dir = {}
    local p = header.dirOffset + 1  -- Lua is 1-based
    for i = 1, header.numLumps do
        local pos, p1 = u32(data, p)
        local size = u32(data, p1)
        local name = name8(data, p1 + 4)
        dir[i] = { pos = pos, size = size, name = name }
        p = p + 16
    end
    return dir
end

-- Return the directory index of a level marker by exact name match, or nil.
local function findLevelMarker(dir, levelName)
    levelName = levelName:upper()
    for i, lump in ipairs(dir) do
        if lump.name == levelName then return i end
    end
    return nil
end

-- Pick the first lump whose name matches the DOOM level naming pattern.
local function findFirstLevel(dir)
    for i, lump in ipairs(dir) do
        if lump.name:match("^E%dM%d$") or lump.name:match("^MAP%d%d$") then
            return i, lump.name
        end
    end
    return nil
end

local function readVertexes(data, pos, size)
    local out = {}
    local end_ = pos + size + 1
    local p = pos + 1
    while p < end_ do
        local x, p1 = s16(data, p)
        local y, p2 = s16(data, p1)
        out[#out + 1] = { x = x, y = y }
        p = p2
    end
    return out
end

local function readLinedefs(data, pos, size)
    local out = {}
    local end_ = pos + size + 1
    local p = pos + 1
    while p < end_ do
        local v1, p1 = s16(data, p)
        local v2, p2 = s16(data, p1)
        local flags, p3 = s16(data, p2)
        local special, p4 = s16(data, p3)
        local tag, p5 = s16(data, p4)
        local right, p6 = s16(data, p5)
        local left,  p7 = s16(data, p6)
        out[#out + 1] = {
            v1 = v1, v2 = v2,
            flags = flags, special = special, tag = tag,
            right = right, left = left,
        }
        p = p7
    end
    return out
end

local function readSidedefs(data, pos, size)
    local out = {}
    local end_ = pos + size + 1
    local p = pos + 1
    while p < end_ do
        local xOff, p1 = s16(data, p)
        local yOff, p2 = s16(data, p1)
        local upper, p3 = name8(data, p2)
        local lower, p4 = name8(data, p3)
        local middle, p5 = name8(data, p4)
        local sectorIdx, p6 = s16(data, p5)
        out[#out + 1] = {
            xOff = xOff, yOff = yOff,
            upper = upper, lower = lower, middle = middle,
            sector = sectorIdx,
        }
        p = p6
    end
    return out
end

local function readThings(data, pos, size)
    local out = {}
    local end_ = pos + size + 1
    local p = pos + 1
    while p < end_ do
        local x, p1 = s16(data, p)
        local y, p2 = s16(data, p1)
        local angle, p3 = s16(data, p2)
        local type_, p4 = s16(data, p3)
        local flags, p5 = s16(data, p4)
        out[#out + 1] = {
            x = x, y = y, angle = angle, type = type_, flags = flags,
        }
        p = p5
    end
    return out
end

local function readSectors(data, pos, size)
    local out = {}
    local end_ = pos + size + 1
    local p = pos + 1
    while p < end_ do
        local floor, p1 = s16(data, p)
        local ceiling, p2 = s16(data, p1)
        local floorTex, p3 = name8(data, p2)
        local ceilTex, p4 = name8(data, p3)
        local light, p5 = s16(data, p4)
        local special, p6 = s16(data, p5)
        local tag, p7 = s16(data, p6)
        out[#out + 1] = {
            floor = floor, ceiling = ceiling,
            floorTex = floorTex, ceilTex = ceilTex,
            light = light, special = special, tag = tag,
        }
        p = p7
    end
    return out
end

-- Parse a WAD and return a single level's lumps. If `levelName` is nil, picks
-- the first ExMx / MAPxx marker. Returns `level, nameUsed` or `nil, err`.
function Wad.loadLevel(data, levelName)
    local header, err = readHeader(data)
    if not header then return nil, err end

    local dir = readDirectory(data, header)

    local markerIdx, foundName
    if levelName then
        markerIdx = findLevelMarker(dir, levelName)
        foundName = levelName:upper()
        if not markerIdx then return nil, "level '" .. levelName .. "' not found" end
    else
        markerIdx, foundName = findFirstLevel(dir)
        if not markerIdx then return nil, "no DOOM level marker found in WAD" end
    end

    local level = { name = foundName }
    -- DOOM levels store their data lumps in the 10 entries following the marker.
    for j = markerIdx + 1, math.min(markerIdx + 10, #dir) do
        local lump = dir[j]
        if lump.name == "VERTEXES" then
            level.vertexes = readVertexes(data, lump.pos, lump.size)
        elseif lump.name == "LINEDEFS" then
            level.linedefs = readLinedefs(data, lump.pos, lump.size)
        elseif lump.name == "SIDEDEFS" then
            level.sidedefs = readSidedefs(data, lump.pos, lump.size)
        elseif lump.name == "SECTORS" then
            level.sectors = readSectors(data, lump.pos, lump.size)
        elseif lump.name == "THINGS" then
            level.things = readThings(data, lump.pos, lump.size)
        end
    end

    if not level.vertexes or not level.linedefs or not level.sidedefs or not level.sectors then
        return nil, "level '" .. foundName .. "' missing required lumps"
    end

    return level, foundName
end

return Wad
