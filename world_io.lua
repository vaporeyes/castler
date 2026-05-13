-- ABOUTME: Serialize / deserialize the voxel world to a compact binary file.
-- ABOUTME: Format: 4-byte magic + u16 version + u16 W/H/D + palette + RLE data.
-- ABOUTME: RLE pairs are (count u16, id u16); palette is (id u16, RGB u8 each).

local bit = require("bit")

local M = {}

local MAGIC   = "CSLR"
local VERSION = 1

-- Little-endian writers building flat strings (joined via table.concat at end).

local function u8(n)
    return string.char(bit.band(n, 0xFF))
end

local function u16(n)
    return string.char(
        bit.band(n, 0xFF),
        bit.band(bit.rshift(n, 8), 0xFF)
    )
end

local function u32(n)
    return string.char(
        bit.band(n, 0xFF),
        bit.band(bit.rshift(n, 8), 0xFF),
        bit.band(bit.rshift(n, 16), 0xFF),
        bit.band(bit.rshift(n, 24), 0xFF)
    )
end

local function readU8(data, pos)
    return data:byte(pos), pos + 1
end

local function readU16(data, pos)
    return bit.bor(data:byte(pos), bit.lshift(data:byte(pos + 1), 8)), pos + 2
end

local function readU32(data, pos)
    return bit.bor(
        bit.bor(data:byte(pos), bit.lshift(data:byte(pos + 1), 8)),
        bit.bor(bit.lshift(data:byte(pos + 2), 16), bit.lshift(data:byte(pos + 3), 24))
    ), pos + 4
end

function M.isSave(data)
    return type(data) == "string" and #data >= 4 and data:sub(1, 4) == MAGIC
end

function M.save(world, filename)
    local parts = {}
    parts[#parts + 1] = MAGIC
    parts[#parts + 1] = u16(VERSION)
    parts[#parts + 1] = u16(world.width)
    parts[#parts + 1] = u16(world.height)
    parts[#parts + 1] = u16(world.depth)

    -- Snapshot the palette so per-sector lit colors from DOOM imports survive
    -- a save/load round trip. Sort by id for stable file output.
    local paletteList = {}
    for id, col in pairs(world.PALETTE) do
        paletteList[#paletteList + 1] = {id, col}
    end
    table.sort(paletteList, function(a, b) return a[1] < b[1] end)

    parts[#parts + 1] = u16(#paletteList)
    for _, e in ipairs(paletteList) do
        local id, col = e[1], e[2]
        parts[#parts + 1] = u16(id)
        parts[#parts + 1] = u8(math.floor((col[1] or 0) * 255 + 0.5))
        parts[#parts + 1] = u8(math.floor((col[2] or 0) * 255 + 0.5))
        parts[#parts + 1] = u8(math.floor((col[3] or 0) * 255 + 0.5))
    end

    -- RLE-encode cell data. Max run length is u16 max so we cap at 65535.
    local data = world.data
    local total = world.size
    local runs = {}
    local i = 1
    while i <= total do
        local id = data[i]
        local count = 1
        while i + count <= total and data[i + count] == id and count < 65535 do
            count = count + 1
        end
        runs[#runs + 1] = u16(count)
        runs[#runs + 1] = u16(id)
        i = i + count
    end

    parts[#parts + 1] = u32(#runs / 2)
    for _, r in ipairs(runs) do parts[#parts + 1] = r end

    local blob = table.concat(parts)
    local ok, err = love.filesystem.write(filename, blob)
    if not ok then return false, err end
    return true, #blob
end

function M.load(world, renderer, data)
    if not M.isSave(data) then return false, "not a Castler save" end

    local version, p = readU16(data, 5)
    if version ~= VERSION then
        return false, "unsupported save version " .. tostring(version)
    end

    local w, p1 = readU16(data, p)
    local h, p2 = readU16(data, p1)
    local d, p3 = readU16(data, p2)

    if w ~= world.width or h ~= world.height or d ~= world.depth then
        return false, string.format(
            "dimension mismatch: file is %dx%dx%d, world is %dx%dx%d",
            w, h, d, world.width, world.height, world.depth)
    end

    -- Wipe any sector-imported palette entries (ids above the user range);
    -- the file we're loading will re-supply whatever it had.
    for id in pairs(world.PALETTE) do
        if id > 5 then world.PALETTE[id] = nil end
    end

    local paletteCount, np = readU16(data, p3)
    p = np
    for _ = 1, paletteCount do
        local id; id, p = readU16(data, p)
        local r; r, p = readU8(data, p)
        local g; g, p = readU8(data, p)
        local b; b, p = readU8(data, p)
        world.PALETTE[id] = { r / 255, g / 255, b / 255 }
    end

    world:clear()
    local cells = world.data
    local writeIdx = 1
    local runs; runs, p = readU32(data, p)
    for _ = 1, runs do
        local count; count, p = readU16(data, p)
        local id;    id,    p = readU16(data, p)
        for _ = 1, count do
            cells[writeIdx] = id
            writeIdx = writeIdx + 1
        end
    end

    renderer:markAllDirty()
    renderer:flushDirty()
    return true
end

M.MAGIC   = MAGIC
M.VERSION = VERSION

return M
