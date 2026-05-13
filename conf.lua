-- ABOUTME: Love2D configuration. Sets window size, title, and enables depth buffer
-- ABOUTME: for hardware-accelerated 3D rendering of the voxel world.

function love.conf(t)
    t.window.title = "Castler"
    t.window.width = 1280
    t.window.height = 720
    t.window.depth = 24
    t.window.resizable = true
    t.window.vsync = 1
end
