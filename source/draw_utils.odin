package arcadia

import rl "vendor:raylib"

draw_model_mesh :: proc(model: rl.Model, mesh_idx: int, transform: rl.Matrix) {
	mesh := model.meshes[mesh_idx]
	mat := model.materials[model.meshMaterial[mesh_idx]]
}
