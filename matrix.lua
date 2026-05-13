-- ABOUTME: Minimal 4x4 matrix math for the 3D pipeline. Matrices are flat
-- ABOUTME: 16-element tables in column-major order, matching Love2D shader:send.

local M = {}

local function vec3_sub(a, b) return {a[1]-b[1], a[2]-b[2], a[3]-b[3]} end
local function vec3_dot(a, b) return a[1]*b[1] + a[2]*b[2] + a[3]*b[3] end
local function vec3_cross(a, b)
    return {
        a[2]*b[3] - a[3]*b[2],
        a[3]*b[1] - a[1]*b[3],
        a[1]*b[2] - a[2]*b[1],
    }
end
local function vec3_norm(v)
    local len = math.sqrt(v[1]*v[1] + v[2]*v[2] + v[3]*v[3])
    if len == 0 then return {0,0,0} end
    return {v[1]/len, v[2]/len, v[3]/len}
end

M.vec3_sub = vec3_sub
M.vec3_dot = vec3_dot
M.vec3_cross = vec3_cross
M.vec3_norm = vec3_norm

function M.identity()
    return {1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1}
end

-- Right-handed perspective matching OpenGL conventions. fovy in radians.
function M.perspective(fovy, aspect, near, far)
    local f = 1 / math.tan(fovy * 0.5)
    local nf = 1 / (near - far)
    return {
        f/aspect, 0, 0,  0,
        0,        f, 0,  0,
        0,        0, (far + near) * nf, -1,
        0,        0, (2 * far * near) * nf, 0,
    }
end

-- Right-handed lookAt. eye/target/up are {x,y,z} tables.
function M.lookAt(eye, target, up)
    local f = vec3_norm(vec3_sub(target, eye))
    local s = vec3_norm(vec3_cross(f, up))
    local u = vec3_cross(s, f)
    return {
        s[1],  u[1], -f[1], 0,
        s[2],  u[2], -f[2], 0,
        s[3],  u[3], -f[3], 0,
        -vec3_dot(s, eye), -vec3_dot(u, eye), vec3_dot(f, eye), 1,
    }
end

-- Column-major multiply: out = a * b.
function M.mul(a, b)
    local r = {}
    for col = 0, 3 do
        for row = 0, 3 do
            local s = 0
            for k = 0, 3 do
                s = s + a[k*4 + row + 1] * b[col*4 + k + 1]
            end
            r[col*4 + row + 1] = s
        end
    end
    return r
end

-- 4x4 inverse via cofactor expansion. Returns nil if singular.
function M.inverse(m)
    local m0,m1,m2,m3   = m[1],  m[2],  m[3],  m[4]
    local m4,m5,m6,m7   = m[5],  m[6],  m[7],  m[8]
    local m8,m9,m10,m11 = m[9],  m[10], m[11], m[12]
    local m12,m13,m14,m15 = m[13], m[14], m[15], m[16]

    local inv = {}
    inv[1]  =  m5*m10*m15 - m5*m11*m14 - m9*m6*m15 + m9*m7*m14 + m13*m6*m11 - m13*m7*m10
    inv[5]  = -m4*m10*m15 + m4*m11*m14 + m8*m6*m15 - m8*m7*m14 - m12*m6*m11 + m12*m7*m10
    inv[9]  =  m4*m9*m15  - m4*m11*m13 - m8*m5*m15 + m8*m7*m13 + m12*m5*m11 - m12*m7*m9
    inv[13] = -m4*m9*m14  + m4*m10*m13 + m8*m5*m14 - m8*m6*m13 - m12*m5*m10 + m12*m6*m9
    inv[2]  = -m1*m10*m15 + m1*m11*m14 + m9*m2*m15 - m9*m3*m14 - m13*m2*m11 + m13*m3*m10
    inv[6]  =  m0*m10*m15 - m0*m11*m14 - m8*m2*m15 + m8*m3*m14 + m12*m2*m11 - m12*m3*m10
    inv[10] = -m0*m9*m15  + m0*m11*m13 + m8*m1*m15 - m8*m3*m13 - m12*m1*m11 + m12*m3*m9
    inv[14] =  m0*m9*m14  - m0*m10*m13 - m8*m1*m14 + m8*m2*m13 + m12*m1*m10 - m12*m2*m9
    inv[3]  =  m1*m6*m15  - m1*m7*m14  - m5*m2*m15 + m5*m3*m14 + m13*m2*m7  - m13*m3*m6
    inv[7]  = -m0*m6*m15  + m0*m7*m14  + m4*m2*m15 - m4*m3*m14 - m12*m2*m7  + m12*m3*m6
    inv[11] =  m0*m5*m15  - m0*m7*m13  - m4*m1*m15 + m4*m3*m13 + m12*m1*m7  - m12*m3*m5
    inv[15] = -m0*m5*m14  + m0*m6*m13  + m4*m1*m14 - m4*m2*m13 - m12*m1*m6  + m12*m2*m5
    inv[4]  = -m1*m6*m11  + m1*m7*m10  + m5*m2*m11 - m5*m3*m10 - m9*m2*m7   + m9*m3*m6
    inv[8]  =  m0*m6*m11  - m0*m7*m10  - m4*m2*m11 + m4*m3*m10 + m8*m2*m7   - m8*m3*m6
    inv[12] = -m0*m5*m11  + m0*m7*m9   + m4*m1*m11 - m4*m3*m9  - m8*m1*m7   + m8*m3*m5
    inv[16] =  m0*m5*m10  - m0*m6*m9   - m4*m1*m10 + m4*m2*m9  + m8*m1*m6   - m8*m2*m5

    local det = m0 * inv[1] + m1 * inv[5] + m2 * inv[9] + m3 * inv[13]
    if det == 0 then return nil end
    local invDet = 1 / det
    for i = 1, 16 do inv[i] = inv[i] * invDet end
    return inv
end

-- Multiply column-major mat4 m by a vec4 (x, y, z, w). Returns x, y, z, w.
function M.mulVec4(m, x, y, z, w)
    return
        m[1]*x + m[5]*y + m[9]*z  + m[13]*w,
        m[2]*x + m[6]*y + m[10]*z + m[14]*w,
        m[3]*x + m[7]*y + m[11]*z + m[15]*w,
        m[4]*x + m[8]*y + m[12]*z + m[16]*w
end

return M
