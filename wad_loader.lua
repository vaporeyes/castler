-- ABOUTME: Minimal DOOM WAD parser. Reads the header, lump directory, and the
-- ABOUTME: four lumps we need to voxelize a level: VERTEXES, LINEDEFS,
-- ABOUTME: SIDEDEFS, SECTORS. Handles vanilla DOOM (not Hexen) linedef format.

local bit = require("bit")

local Wad = {}

local function ensureBytes(data, pos, count, context)
    if count == 0 then return true end
    if pos < 1 or pos + count - 1 > #data then
        return nil, string.format("%s extends past end of file", context)
    end
    return true
end

local function validateLump(data, lump, recordSize, name)
    if lump.size % recordSize ~= 0 then
        return nil, string.format("%s lump has invalid size %d", name, lump.size)
    end
    return ensureBytes(data, lump.pos + 1, lump.size, name .. " lump")
end

local function u8(data, pos, context)
    local ok, err = ensureBytes(data, pos, 1, context or "u8")
    if not ok then return nil, pos, err end
    return data:byte(pos), pos + 1
end

local function u16(data, pos, context)
    local ok, err = ensureBytes(data, pos, 2, context or "u16")
    if not ok then return nil, pos, err end
    return bit.bor(data:byte(pos), bit.lshift(data:byte(pos + 1), 8)), pos + 2
end

local function s16(data, pos, context)
    local v, p, err = u16(data, pos, context or "s16")
    if not v then return nil, pos, err end
    if v >= 0x8000 then v = v - 0x10000 end
    return v, p
end

local function u32(data, pos, context)
    local ok, err = ensureBytes(data, pos, 4, context or "u32")
    if not ok then return nil, pos, err end
    local b1 = data:byte(pos)
    local b2 = data:byte(pos + 1)
    local b3 = data:byte(pos + 2)
    local b4 = data:byte(pos + 3)
    return bit.bor(
        bit.bor(b1, bit.lshift(b2, 8)),
        bit.bor(bit.lshift(b3, 16), bit.lshift(b4, 24))
    ), pos + 4
end

local function name8(data, pos, context)
    local ok, err = ensureBytes(data, pos, 8, context or "name")
    if not ok then return nil, pos, err end
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
    local numLumps, p = u32(data, 5, "WAD lump count")
    local dirOffset = u32(data, 9, "WAD directory offset")
    if not numLumps or not dirOffset then
        return nil, "file too short for WAD header"
    end
    local dirStart = dirOffset + 1
    local dirSize = numLumps * 16
    local ok, err = ensureBytes(data, dirStart, dirSize, "WAD directory")
    if not ok then return nil, err end
    return { magic = magic, numLumps = numLumps, dirOffset = dirOffset }
end

local function readDirectory(data, header)
    local dir = {}
    local p = header.dirOffset + 1  -- Lua is 1-based
    for i = 1, header.numLumps do
        local pos, p1, err = u32(data, p, "WAD directory lump position")
        if not pos then return nil, err end
        local size; size, p1, err = u32(data, p1, "WAD directory lump size")
        if not size then return nil, err end
        local name; name, _, err = name8(data, p1, "WAD directory lump name")
        if not name then return nil, err end
        local ok
        ok, err = ensureBytes(data, pos + 1, size, "WAD lump " .. name)
        if not ok then return nil, err end
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
        local x, p1, err = s16(data, p, "VERTEXES x")
        if not x then return nil, err end
        local y, p2; y, p2, err = s16(data, p1, "VERTEXES y")
        if not y then return nil, err end
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
        local v1, p1, err = s16(data, p, "LINEDEFS v1")
        if not v1 then return nil, err end
        local v2, p2; v2, p2, err = s16(data, p1, "LINEDEFS v2")
        if not v2 then return nil, err end
        local flags, p3; flags, p3, err = s16(data, p2, "LINEDEFS flags")
        if not flags then return nil, err end
        local special, p4; special, p4, err = s16(data, p3, "LINEDEFS special")
        if not special then return nil, err end
        local tag, p5; tag, p5, err = s16(data, p4, "LINEDEFS tag")
        if not tag then return nil, err end
        local right, p6; right, p6, err = s16(data, p5, "LINEDEFS right sidedef")
        if not right then return nil, err end
        local left, p7; left, p7, err = s16(data, p6, "LINEDEFS left sidedef")
        if not left then return nil, err end
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
        local xOff, p1, err = s16(data, p, "SIDEDEFS x offset")
        if not xOff then return nil, err end
        local yOff, p2; yOff, p2, err = s16(data, p1, "SIDEDEFS y offset")
        if not yOff then return nil, err end
        local upper, p3; upper, p3, err = name8(data, p2, "SIDEDEFS upper texture")
        if not upper then return nil, err end
        local lower, p4; lower, p4, err = name8(data, p3, "SIDEDEFS lower texture")
        if not lower then return nil, err end
        local middle, p5; middle, p5, err = name8(data, p4, "SIDEDEFS middle texture")
        if not middle then return nil, err end
        local sectorIdx, p6; sectorIdx, p6, err = s16(data, p5, "SIDEDEFS sector")
        if not sectorIdx then return nil, err end
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
        local x, p1, err = s16(data, p, "THINGS x")
        if not x then return nil, err end
        local y, p2; y, p2, err = s16(data, p1, "THINGS y")
        if not y then return nil, err end
        local angle, p3; angle, p3, err = s16(data, p2, "THINGS angle")
        if not angle then return nil, err end
        local type_, p4; type_, p4, err = s16(data, p3, "THINGS type")
        if not type_ then return nil, err end
        local flags, p5; flags, p5, err = s16(data, p4, "THINGS flags")
        if not flags then return nil, err end
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
        local floor, p1, err = s16(data, p, "SECTORS floor height")
        if not floor then return nil, err end
        local ceiling, p2; ceiling, p2, err = s16(data, p1, "SECTORS ceiling height")
        if not ceiling then return nil, err end
        local floorTex, p3; floorTex, p3, err = name8(data, p2, "SECTORS floor texture")
        if not floorTex then return nil, err end
        local ceilTex, p4; ceilTex, p4, err = name8(data, p3, "SECTORS ceiling texture")
        if not ceilTex then return nil, err end
        local light, p5; light, p5, err = s16(data, p4, "SECTORS light")
        if not light then return nil, err end
        local special, p6; special, p6, err = s16(data, p5, "SECTORS special")
        if not special then return nil, err end
        local tag, p7; tag, p7, err = s16(data, p6, "SECTORS tag")
        if not tag then return nil, err end
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

    local dir; dir, err = readDirectory(data, header)
    if not dir then return nil, err end

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
            local ok; ok, err = validateLump(data, lump, 4, "VERTEXES")
            if not ok then return nil, err end
            level.vertexes, err = readVertexes(data, lump.pos, lump.size)
            if not level.vertexes then return nil, err end
        elseif lump.name == "LINEDEFS" then
            local ok; ok, err = validateLump(data, lump, 14, "LINEDEFS")
            if not ok then return nil, err end
            level.linedefs, err = readLinedefs(data, lump.pos, lump.size)
            if not level.linedefs then return nil, err end
        elseif lump.name == "SIDEDEFS" then
            local ok; ok, err = validateLump(data, lump, 30, "SIDEDEFS")
            if not ok then return nil, err end
            level.sidedefs, err = readSidedefs(data, lump.pos, lump.size)
            if not level.sidedefs then return nil, err end
        elseif lump.name == "SECTORS" then
            local ok; ok, err = validateLump(data, lump, 26, "SECTORS")
            if not ok then return nil, err end
            level.sectors, err = readSectors(data, lump.pos, lump.size)
            if not level.sectors then return nil, err end
        elseif lump.name == "THINGS" then
            local ok; ok, err = validateLump(data, lump, 10, "THINGS")
            if not ok then return nil, err end
            level.things, err = readThings(data, lump.pos, lump.size)
            if not level.things then return nil, err end
        end
    end

    if not level.vertexes or not level.linedefs or not level.sidedefs or not level.sectors then
        return nil, "level '" .. foundName .. "' missing required lumps"
    end

    return level, foundName
end

return Wad
