### Phase 1: Data & Rendering (The Foundation)

#### Prompt 1: The Voxel Data Manager

> **Task:** Create a `voxel_world.lua` module.
> **Requirements:**
> 1. Define fixed world dimensions (`width`, `height`, `depth`).
> 2. Store block data in a flat 1D table for cache locality. Provide `getIndex(x, y, z)` and `getXYZ(index)` helper functions.
> 3. Provide `getBlock(x, y, z)` and `setBlock(x, y, z, id)` methods. Handle out-of-bounds queries gracefully (return 0 / false).
> 4. `0` represents Air. Any other integer represents a Block ID.
> 5. Initialize a "floor" layer at `y=1` (Lua uses 1-based indexing).
> 6. Include an iterator or traversal method optimized for bulk reads.
> 
> 

#### Prompt 2: The 3D Mesh & Shader Pipeline

> **Task:** Create a `chunk_renderer.lua` module and the necessary GLSL shader code.
> **Context:** Love2D is inherently 2D. We must build a hardware-accelerated 3D pipeline.
> **Requirements:**
> 1. **Shader:** Write a Love2D vertex shader to handle the Model-View-Projection (MVP) matrix multiplication.
> 2. **Mesh Generation:** Iterate through `voxel_world`. Generate vertex positions `(x,y,z)` and colors `(r,g,b)`.
> 3. **Face Culling:** Only push vertices/indices for faces adjacent to Air (`0`) or out-of-bounds coordinates.
> 4. **Mesh Object:** Construct a `love.graphics.newMesh` using the standard `VertexPosition` and `VertexColor` attributes. Set the draw mode to `triangles`.
> 5. Include a `regenerateMesh(voxel_world)` function. Minimize table reallocation during this process to avoid GC spikes.
> 6. Expose a `draw(viewMatrix, projectionMatrix)` method that sets `love.graphics.setDepthMode("less", true)` and executes the shader.
> 
> 

---

### Phase 2: Interaction (The "Hand")

#### Prompt 3: The RTS Camera

> **Task:** Create an `rts_camera.lua` module.
> **Requirements:**
> 1. **State:** Maintain camera position, target (look-at point), FOV, pitch, and yaw.
> 2. **Matrices:** Implement functions to calculate and return the View Matrix (using `lookAt` math) and Projection Matrix (Perspective).
> 3. **Movement:** WASD translates the target point along the X/Z plane.
> 4. **Zoom:** Mouse wheel interpolates the camera distance from the target.
> 5. **Rotation:** Right-click + drag alters pitch and yaw (spherical coordinates orbiting the target).
> 6. **Smoothing:** Apply linear interpolation (`lerp`) or smooth dampening to movement and rotation parameters.
> 
> 

#### Prompt 4: 3D Raycasting (DDA) & Block Modification

> **Task:** Create a `build_manager.lua` module.
> **Requirements:**
> 1. **Raycasting:** Implement a 3D Digital Differential Analyzer (DDA) algorithm.
> 
> 
> * Input: Ray origin (camera position) and direction (unprojected mouse coordinates).
> * Output: The `(x, y, z)` of the intersected block and the surface normal `(nx, ny, nz)` of the hit face.
> 
> 
> 2. **Ghosting:** Render a wireframe cube (using `love.graphics.line` mapped through the MVP matrix) at the `hit_position + normal`.
> 3. **Input:** Left Click places a block at `hit_position + normal`. Shift + Left Click removes the block at `hit_position`.
> 4. Call `voxel_world:setBlock()` and trigger `chunk_renderer:regenerateMesh()` upon successful modification.
> 
> 

---

### Phase 3: Physics (The Engineering)

#### Prompt 5: Structural Integrity Algorithm

> **Task:** Create a `structural_integrity.lua` module.
> **Requirements:**
> 1. Implement a **Breadth-First Search (BFS)** algorithm tailored for 3D grids.
> 2. **Logic:** A block is stable if it rests at `y=1` or is contiguously connected to a stable neighbor.
> 3. **Trigger:** `checkStability(removed_x, removed_y, removed_z)`. When a block is destroyed, check adjacent blocks.
> 4. **Optimization:** Maintain a pre-allocated queue table for the BFS to prevent memory thrashing.
> 5. **Execution:** Identify all disconnected sub-graphs. Set their voxel data to `0`. Return a list of collapsed block coordinates for external particle generation.
> 
> 

---

### Phase 4: UI & Polish

#### Prompt 6: 2D Overlay & Palette UI

> **Task:** Implement the `ui_manager.lua` module.
> **Requirements:**
> 1. Ensure `love.graphics.setDepthMode()` is disabled before rendering UI so it draws over the 3D scene.
> 2. Listen for number keys (1-5) via `love.keypressed`.
> 3. Map keys to block IDs/colors (e.g., 1 = Stone/Grey, 2 = Wood/Brown).
> 4. Update state in `build_manager.lua`.
> 5. Render a minimalist HUD displaying the currently selected block type and FPS (`love.timer.getFPS()`) using `love.graphics.print`.
> 
>