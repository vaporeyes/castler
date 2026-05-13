### Phase 1: The Bedrock (Data & Rendering)

* **Step 1: Define the Voxel Data Structure.** Create a Lua module (`world_data.lua`) containing a pre-allocated 1D table to simulate a 3D grid. Map integer IDs to RGB values using a static lookup table (e.g., `1 = {0.5, 0.5, 0.5}, 2 = {0.6, 0.4, 0.2}`).
* **Step 2: Basic Mesh Generation.** Write an iterator to traverse the `world_data` table. For every solid block, calculate the 1D indices of its 6 spatial neighbors. If a neighbor index returns `0` (Air) or is out of bounds, construct a quad (4 vertices, 6 indices) for that face.
* **Step 3: Vertex Coloring & Shaders.** Define a custom vertex format for `love.graphics.newMesh` that includes `VertexPosition` and `VertexColor`. Write a Love2D GLSL vertex shader to handle the Model-View-Projection (MVP) matrix transformation and pass the vertex colors to the fragment shader.
* **Step 4: Optimization (Chunking for Meshes).** To avoid Lua garbage collection spikes and FFI transfer overhead to the GPU, partition the world into smaller spatial chunks (e.g., 16x16x16). Each chunk manages its own `love.graphics.newMesh`. When a block is modified, only rebuild the mesh for that specific chunk.

### Phase 2: The Hand (Input & Camera)

* **Step 5: RTS Camera Controller.** Implement a camera module that calculates View and Projection matrices. Support Panning (WASD mapped to the camera's local X/Z vectors relative to the ground plane), Zooming (Mouse Wheel to scale the radius from the pivot point), and Rotation (Right-click + drag to modify spherical pitch and yaw coordinates).
* **Step 6: The "Ghost" Block.** Implement a 3D Digital Differential Analyzer (DDA) raycast. Project a ray from the camera's near plane into the world using the inverse MVP matrix. Calculate the exact integer coordinate `(x,y,z)` of the hit and the surface normal. Render a wireframe cube using `love.graphics.line` transformed by the MVP matrix to indicate placement/removal targets.
* **Step 7: Modification Logic.** Write the `setBlock(x, y, z, id)` function. Upon left-click, update the 1D table at the hit coordinate + normal. **Edge Case:** If the modified block lies on a chunk boundary, trigger a mesh rebuild for both the target chunk and the adjacent chunk to ensure face culling updates correctly.

### Phase 3: The Laws of Physics (Structural Integrity)

* **Step 8: Stability Algorithm.** Implement a Breadth-First Search (BFS). Avoid deep recursion (DFS) to prevent Lua stack overflows. When a block is *removed*:
1. Identify all adjacent solid blocks.
2. Run the BFS outward from those neighbors to find a path to `y=1`.
3. If a contiguous group of blocks returns no path to the ground, set their 1D table indices to `0`.


* **Step 9: Visual Feedback for Stability.** When blocks are removed via the BFS cascade, return their coordinates to the main loop. Spawn lightweight 2D quads in a particle system module that update via a simple gravity vector (`y = y - 9.8 * dt`) before despawning.

### Phase 4: The Interface (UI)

* **Step 10: Hotbar/Palette System.** Build a `ui.lua` module. Disable depth testing (`love.graphics.setDepthMode()`) before rendering. Use `love.keypressed` to map number keys (1-9) to the active block ID. Render a 2D hotbar using `love.graphics.rectangle` directly to the screen overlay.