-- ABOUTME: Converts a parsed DOOM level (from wad_loader) into voxel placements.
-- ABOUTME: Scales to fit the world, scanline-fills each sector's polygon, and
-- ABOUTME: stamps single-sided linedefs as wall columns.

local Voxelizer = {}

-- 0xFFFF (no sidedef) comes through s16 as -1.
local NO_SIDEDEF = -1

-- DOOM's sentinel ceiling texture for "open sky"; the ceiling height for
-- these sectors is decorative, not a real wall height.
local SKY_TEX = "F_SKY1"

local function isSkySector(sector)
    return sector.ceilTex == SKY_TEX
end

-- One "standard" DOOM wall height. Used as the wall cap for sky sectors so
-- outdoor parapets aren't rendered as skyscrapers reaching world.height.
local DOOM_STANDARD_WALL = 128

-- Base colors cycled across sectors before light-level modulation. These are
-- intentionally muted so multiplying by sector light produces DOOM's grimy
-- palette rather than saturated colors.
local SECTOR_BASE_COLORS = {
    {0.62, 0.55, 0.45},  -- warm stone
    {0.55, 0.42, 0.30},  -- brown
    {0.48, 0.48, 0.50},  -- cold gray
    {0.50, 0.55, 0.42},  -- mossy
    {0.65, 0.58, 0.40},  -- tan
}

-- Palette ID ranges for per-sector colors. Kept well above the user palette
-- (1..5) so the hotbar stays untouched.
local FLOOR_ID_BASE = 100
local CEIL_ID_BASE  = 200

-- Minimum light so dim sectors aren't pitch black against fog.
local MIN_LIGHT = 0.22

local function sectorPaletteId(sIdx, isCeiling)
    return (isCeiling and CEIL_ID_BASE or FLOOR_ID_BASE) + sIdx
end

local function buildSectorPalette(world, level)
    for sIdx, sector in ipairs(level.sectors) do
        local base = SECTOR_BASE_COLORS[((sIdx - 1) % #SECTOR_BASE_COLORS) + 1]
        local L = math.max(MIN_LIGHT, math.min(1, sector.light / 255))
        world.PALETTE[sectorPaletteId(sIdx, false)] = {
            base[1] * L, base[2] * L, base[3] * L,
        }
        -- Ceilings render a bit darker than floors so the inside of a room
        -- reads correctly even without overhead lighting.
        local cL = L * 0.70
        world.PALETTE[sectorPaletteId(sIdx, true)] = {
            base[1] * cL, base[2] * cL, base[3] * cL,
        }
    end
end

local function sectorOf(level, sidedefIndex)
    if sidedefIndex == NO_SIDEDEF or sidedefIndex < 0 then return nil end
    local sd = level.sidedefs[sidedefIndex + 1]
    if not sd then return nil end
    local sec = level.sectors[sd.sector + 1]
    if not sec then return nil end
    return sec, sd.sector + 1
end

-- Collect (x1, y1, x2, y2) edges in DOOM map space that bound `sectorIdx`.
local function collectSectorEdges(level, sectorIdx)
    local edges = {}
    for _, ld in ipairs(level.linedefs) do
        local _, secA = sectorOf(level, ld.right)
        local _, secB = sectorOf(level, ld.left)
        if secA == sectorIdx or secB == sectorIdx then
            local v1 = level.vertexes[ld.v1 + 1]
            local v2 = level.vertexes[ld.v2 + 1]
            if v1 and v2 then
                edges[#edges + 1] = { x1 = v1.x, y1 = v1.y, x2 = v2.x, y2 = v2.y }
            end
        end
    end
    return edges
end

-- Compute scale + offset so the map fills the world with a small margin.
local function computeTransform(level, world)
    local minX, maxX = math.huge, -math.huge
    local minY, maxY = math.huge, -math.huge
    for _, v in ipairs(level.vertexes) do
        if v.x < minX then minX = v.x end
        if v.x > maxX then maxX = v.x end
        if v.y < minY then minY = v.y end
        if v.y > maxY then maxY = v.y end
    end

    local minH, maxH = math.huge, -math.huge
    for _, s in ipairs(level.sectors) do
        if s.floor < minH then minH = s.floor end
        -- Sky ceilings are sentinel values (often 256-1024). Excluding them
        -- prevents scaleY from being dominated by outdoor sentinels and makes
        -- interior walls land at sensible heights.
        if not isSkySector(s) and s.ceiling > maxH then maxH = s.ceiling end
    end
    if maxH == -math.huge then maxH = minH + DOOM_STANDARD_WALL end

    local margin = 4
    local usableW = world.width  - margin * 2
    local usableD = world.depth  - margin * 2
    local mapW = math.max(1, maxX - minX)
    local mapD = math.max(1, maxY - minY)
    -- Single XZ scale to preserve aspect ratio.
    local scaleXZ = math.max(mapW / usableW, mapD / usableD)

    -- Y scale: prefer aspect-correct (a voxel cube == the same DOOM units on
    -- every axis) so walls render at their real proportions instead of as
    -- towers. Only fall back to "fit to world.height" if the level's vertical
    -- range would actually overflow at the aspect-correct scale.
    local usableH = world.height - 4
    local mapHRange = math.max(1, maxH - minH)
    local scaleY = scaleXZ
    if mapHRange / scaleY > usableH then
        scaleY = mapHRange / usableH
    end

    return {
        minX = minX, maxX = maxX,
        minY = minY, maxY = maxY,
        minH = minH,
        scaleXZ = scaleXZ, scaleY = scaleY,
        margin = margin,
        worldW = world.width, worldH = world.height, worldD = world.depth,
    }
end

local function txX(t, x) return (x - t.minX) / t.scaleXZ + t.margin end
-- DOOM map space uses +Y = north (top of the editor's 2D view). Negating the
-- mapping makes DOOM north end up at low world Z so the result reads the same
-- way as the editor's wireframe instead of mirrored.
local function txZ(t, y) return (t.maxY - y) / t.scaleXZ + t.margin end
local function txY(t, h)
    -- Floor=1 is the lowest possible solid cell; everything else stacks on it.
    return math.max(1, math.floor((h - t.minH) / t.scaleY) + 1)
end

-- Scanline fill the polygon defined by `edges` (in DOOM coords) at each integer
-- world Z, calling fn(x, z) for every interior cell.
local function rasterizePolygon(edges, t, fn)
    -- Pre-transform edge endpoints into world XZ space.
    local we = {}
    local zMinW, zMaxW = math.huge, -math.huge
    for _, e in ipairs(edges) do
        local wx1 = txX(t, e.x1); local wz1 = txZ(t, e.y1)
        local wx2 = txX(t, e.x2); local wz2 = txZ(t, e.y2)
        we[#we + 1] = { x1 = wx1, z1 = wz1, x2 = wx2, z2 = wz2 }
        if wz1 < zMinW then zMinW = wz1 end
        if wz2 < zMinW then zMinW = wz2 end
        if wz1 > zMaxW then zMaxW = wz1 end
        if wz2 > zMaxW then zMaxW = wz2 end
    end

    local zStart = math.max(1, math.floor(zMinW))
    local zEnd   = math.min(t.worldD, math.ceil(zMaxW))
    local intersections = {}

    for z = zStart, zEnd do
        -- Sample at the cell's center to avoid degenerate vertex-row hits.
        local scanZ = z - 0.5
        local count = 0
        for i = 1, #we do
            local e = we[i]
            local z1, z2 = e.z1, e.z2
            local x1, x2 = e.x1, e.x2
            if z1 > z2 then z1, z2 = z2, z1; x1, x2 = x2, x1 end
            -- Half-open: include lower endpoint, exclude upper. Drops horizontal edges.
            if scanZ >= z1 and scanZ < z2 then
                local pt = (scanZ - z1) / (z2 - z1)
                count = count + 1
                intersections[count] = x1 + pt * (x2 - x1)
            end
        end
        if count >= 2 then
            -- Truncate any leftovers from previous longer rows.
            for i = count + 1, #intersections do intersections[i] = nil end
            table.sort(intersections)
            for i = 1, count - 1, 2 do
                local xa = intersections[i]
                local xb = intersections[i + 1]
                local xs = math.max(1,         math.ceil(xa))
                local xe = math.min(t.worldW,  math.floor(xb))
                for x = xs, xe do
                    fn(x, z)
                end
            end
        end
    end
end

-- Stamp a wall column along a line from (x1,z1) to (x2,z2), at every integer
-- cell the segment crosses, filling y in [yLo..yHi].
local function stampWall(world, x1, z1, x2, z2, yLo, yHi, id)
    local dx = x2 - x1
    local dz = z2 - z1
    local n = math.max(math.abs(dx), math.abs(dz))
    -- Oversample so we don't leave gaps in shallow diagonals.
    local steps = math.max(1, math.ceil(n * 2))
    for i = 0, steps do
        local pt = i / steps
        local x = math.floor(x1 + dx * pt + 0.5)
        local z = math.floor(z1 + dz * pt + 0.5)
        for y = yLo, yHi do
            if world:inBounds(x, y, z) then
                world:setBlock(x, y, z, id)
            end
        end
    end
end

function Voxelizer.import(world, renderer, level)
    local t = computeTransform(level, world)
    world:clear()
    buildSectorPalette(world, level)

    -- Each sector fills its polygon up to floorY, and (unless it's a sky
    -- sector) stamps a one-block-thick ceiling slab at ceilY. The ceiling
    -- uses a darker variant of the same hue so it reads as overhead.
    for sIdx, sector in ipairs(level.sectors) do
        local floorId = sectorPaletteId(sIdx, false)
        local ceilId  = sectorPaletteId(sIdx, true)
        local floorY  = txY(t, sector.floor)
        local sky     = isSkySector(sector)
        local ceilY   = sky and -1 or math.min(world.height, txY(t, sector.ceiling))

        local edges = collectSectorEdges(level, sIdx)
        if #edges >= 3 then
            rasterizePolygon(edges, t, function(x, z)
                for y = 1, floorY do
                    world:setBlock(x, y, z, floorId)
                end
                if not sky and ceilY > floorY then
                    world:setBlock(x, ceilY, z, ceilId)
                end
            end)
        end
    end

    -- Single-sided linedefs become solid walls. Wall height = sector ceiling
    -- (capped to world height); base = sector floor + 1 so we don't overwrite
    -- the walkable surface stripe. Walls inherit their owning sector's lit
    -- palette ID so light level + fog read correctly across the whole room.
    local skyWallVoxels = math.max(2, math.floor(DOOM_STANDARD_WALL / t.scaleY))

    local function sectorIndexOf(sidedefIndex)
        if sidedefIndex == NO_SIDEDEF or sidedefIndex < 0 then return nil end
        local sd = level.sidedefs[sidedefIndex + 1]
        if not sd then return nil end
        return sd.sector + 1
    end

    for _, ld in ipairs(level.linedefs) do
        if ld.left == NO_SIDEDEF then
            local secIdx = sectorIndexOf(ld.right)
            local sec = secIdx and level.sectors[secIdx]
            if sec then
                local v1 = level.vertexes[ld.v1 + 1]
                local v2 = level.vertexes[ld.v2 + 1]
                if v1 and v2 then
                    local x1, z1 = txX(t, v1.x), txZ(t, v1.y)
                    local x2, z2 = txX(t, v2.x), txZ(t, v2.y)
                    local floorY = txY(t, sec.floor)
                    local ceilY
                    if isSkySector(sec) then
                        ceilY = math.min(world.height, floorY + skyWallVoxels)
                    else
                        ceilY = math.min(world.height, txY(t, sec.ceiling))
                    end
                    if ceilY > floorY then
                        stampWall(world, x1, z1, x2, z2, floorY + 1, ceilY,
                            sectorPaletteId(secIdx, false))
                    end
                end
            end
        else
            -- Two-sided step: use the higher sector's color so the rise reads
            -- as part of the room the player is stepping into.
            local fIdx = sectorIndexOf(ld.right)
            local bIdx = sectorIndexOf(ld.left)
            local secF = fIdx and level.sectors[fIdx]
            local secB = bIdx and level.sectors[bIdx]
            if secF and secB and secF.floor ~= secB.floor then
                local higherIdx = (secF.floor > secB.floor) and fIdx or bIdx
                local loF = math.min(secF.floor, secB.floor)
                local hiF = math.max(secF.floor, secB.floor)
                local loFY = txY(t, loF)
                local hiFY = txY(t, hiF)
                if hiFY > loFY then
                    local v1 = level.vertexes[ld.v1 + 1]
                    local v2 = level.vertexes[ld.v2 + 1]
                    if v1 and v2 then
                        local x1, z1 = txX(t, v1.x), txZ(t, v1.y)
                        local x2, z2 = txX(t, v2.x), txZ(t, v2.y)
                        stampWall(world, x1, z1, x2, z2, loFY + 1, hiFY,
                            sectorPaletteId(higherIdx, false))
                    end
                end
            end
        end
    end

    renderer:markAllDirty()
    renderer:flushDirty()

    -- Find Player 1 start (THING type 1). DOOM angle is measured CCW from east
    -- in degrees; our fly camera's yaw=0 looks toward -Z (which after the Z
    -- flip is DOOM north / +Y). Conversion: fly_yaw = doom_angle_rad - pi/2.
    local playerStart = nil
    if level.things then
        for _, thing in ipairs(level.things) do
            if thing.type == 1 then
                local sx = txX(t, thing.x)
                local sz = txZ(t, thing.y)
                if world:inBounds(math.floor(sx + 0.5), 1, math.floor(sz + 0.5)) then
                    -- Spawn at the floor of whatever column the player sits in,
                    -- + a couple of voxels so we're standing, not embedded.
                    local cellX = math.max(1, math.min(world.width, math.floor(sx + 0.5)))
                    local cellZ = math.max(1, math.min(world.depth, math.floor(sz + 0.5)))
                    local groundY = 1
                    for y = world.height, 1, -1 do
                        if world:getBlock(cellX, y, cellZ) ~= 0 then
                            groundY = y + 1
                            break
                        end
                    end
                    playerStart = {
                        x = sx,
                        y = math.min(world.height - 1, groundY + 1),
                        z = sz,
                        yaw = math.rad(thing.angle) - math.pi * 0.5,
                    }
                end
                break
            end
        end
    end

    return t, playerStart
end

return Voxelizer
