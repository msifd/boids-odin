package arcadia

import "core:c/libc"
import "core:log"
import rl "vendor:raylib"

RES_BOID :: #load("../assets/boid.glb")

Shader_Type :: enum {
	INSTANCING_VERT,
	INSTANCING_FRAG,
}
SHADERS :: [Shader_Type]cstring {
	.INSTANCING_VERT = #load("../assets/basic_instancing.vs", cstring),
	.INSTANCING_FRAG = #load("../assets/basic_instancing.fs", cstring),
}

GAME_VOLUME_A :: rl.Vector3{100, 100, 100}
GAME_VOLUME_B :: rl.Vector3{-100, -100, -100}

Boid :: struct {
	pos: rl.Vector3,
	vel: rl.Vector3,
}

Game_State :: struct {
	boid_model:   rl.Model,
	camera:       rl.Camera3D,
	boids:        [dynamic]Boid,
	// boid_transforms: [dynamic]rl.Matrix,
	cube:         rl.Mesh,
	cube_mat:     rl.Material,
	cube_mat_def: rl.Material,
}

state: ^Game_State

@(export)
game_window_init :: proc() {
	WINDOW_WIDHT :: 854
	WINDOW_HEIGHT :: 480

	rl.SetConfigFlags({.VSYNC_HINT, .WINDOW_RESIZABLE})
	rl.InitWindow(WINDOW_WIDHT, WINDOW_HEIGHT, "Boids")
	rl.SetTargetFPS(rl.GetMonitorRefreshRate(rl.GetCurrentMonitor()) + 1)
}

load_raylib_file: rl.LoadFileDataCallback : proc "c" (filename: cstring, data_len: ^i32) -> [^]u8 {
	orig_data: []u8

	switch filename {
	case "boid.glb":
		orig_data = RES_BOID
	case:
		return nil
	}

	len := len(orig_data)
	data_copy := libc.malloc(uint(len))
	libc.memcpy(data_copy, raw_data(orig_data), uint(len))
	data_len^ = i32(len)
	ptr := cast([^]u8)data_copy
	return ptr
}

AMB_COLOR := rl.Vector4{0.2, 0.2, 0.2, 1.0}

// MARK: game_memory_init
@(export)
game_memory_init :: proc() -> rawptr {
	rl.SetLoadFileDataCallback(load_raylib_file)

	s := new(Game_State)

	using rl.ShaderLocationIndex
	instancing_shader := rl.LoadShaderFromMemory(
		SHADERS[.INSTANCING_VERT],
		SHADERS[.INSTANCING_FRAG],
	)
	// instancing_shader := rl.LoadShader("assets/basic_instancing.vs", "assets/basic_instancing.fs")
	instancing_shader.locs[MATRIX_MVP] = rl.GetShaderLocation(instancing_shader, "mvp")
	instancing_shader.locs[VECTOR_VIEW] = rl.GetShaderLocation(instancing_shader, "viewPos")
	rl.SetShaderValue(
		instancing_shader,
		rl.GetShaderLocation(instancing_shader, "ambient"),
		&AMB_COLOR,
		.VEC4,
	)

	s.cube = rl.GenMeshCube(1, 1, 1)

	cube_mat := rl.LoadMaterialDefault()
	cube_mat.shader = instancing_shader
	cube_mat.maps[rl.MaterialMapIndex.ALBEDO].color = rl.RED
	s.cube_mat = cube_mat

	cube_mat_def := rl.LoadMaterialDefault()
	cube_mat_def.maps[rl.MaterialMapIndex.ALBEDO].color = rl.BLUE
	s.cube_mat_def = cube_mat_def

	log.debug("shaders", cube_mat.shader.id, cube_mat_def.shader.id, rl.LoadMaterialDefault().shader.id)

	// model := rl.LoadModel("boid.glb")
	// model.materials[0].maps[0].texture = model.materials[1].maps[0].texture
	// model.materials[1].shader = instancing_shader
	// model.materials[1].maps[rl.MaterialMapIndex.ALBEDO].color = rl.WHITE
	// s.boid_model = model

	s.camera = rl.Camera3D {
		position   = {100, 50, 250},
		target     = {0, 0, 0},
		up         = {0, 1, 0},
		fovy       = 60,
		projection = .PERSPECTIVE,
	}

	create_boids(s)

	return s
}
@(export)
game_memory_cleanup :: proc(s: ^Game_State) {
	clear_dynamic_array(&s.boids)
	// clear_dynamic_array(&s.boid_transforms)
	delete(s.boids)
	// delete(s.boid_transforms)

	rl.UnloadModel(s.boid_model)
	rl.UnloadMesh(s.cube)
	rl.UnloadMaterial(s.cube_mat)
	rl.UnloadMaterial(s.cube_mat_def)
}

// MARK: create_boids
create_boids :: proc(s: ^Game_State) {
	clear_dynamic_array(&s.boids)
	// clear_dynamic_array(&s.boid_transforms)

	BOIDS_COUNT :: 100
	reserve_dynamic_array(&s.boids, BOIDS_COUNT)
	// reserve_dynamic_array(&s.boid_transforms, BOIDS_COUNT)

	PREC :: 10
	GVA: [3]i32 = {i32(GAME_VOLUME_A.x), i32(GAME_VOLUME_A.y), i32(GAME_VOLUME_A.z)}
	GVB: [3]i32 = {i32(GAME_VOLUME_B.x), i32(GAME_VOLUME_B.y), i32(GAME_VOLUME_B.z)}
	GVA = GVA * PREC - PREC
	GVB = GVB * PREC + PREC

	SCALE :: 8
	scale_mx := rl.MatrixScale(SCALE, SCALE, SCALE)

	for _ in 0 ..< BOIDS_COUNT {
		pos := rl.Vector3 {
			f32(rl.GetRandomValue(GVB.x, GVA.x)),
			f32(rl.GetRandomValue(GVB.y, GVA.y)),
			f32(rl.GetRandomValue(GVB.z, GVA.z)),
		}
		pos /= PREC
		vel := rl.Vector3 {
			f32(rl.GetRandomValue(-10, 10) / 5),
			f32(rl.GetRandomValue(-10, 10) / 5),
			f32(rl.GetRandomValue(-10, 10) / 5),
		}

		append(&s.boids, Boid{pos, vel})
	}
}

// MARK: boid_apply_forces
boid_apply_forces :: proc(b: Boid, delta: f32) -> (pos: rl.Vector3, vel: rl.Vector3) {
	using rl

	EFFECT_RADIUS_SQRT :: 20 * 20
	DESIRED_SEPARATION_SQRT :: 8 * 8
	MAX_SPEED :: 50.
	MAX_FORCE :: 0.5

	COH_WEIGHT :: 1.0
	ALI_WEIGHT :: 1.0
	SEP_WEIGHT :: 1.5

	neighbors: f32
	per_center: Vector3
	per_vel: Vector3
	sep_vel: Vector3

	for n in state.boids {
		dist := Vector3DistanceSqrt(b.pos, n.pos)
		if dist == 0 || dist > EFFECT_RADIUS_SQRT {
			continue
		}

		neighbors += 1
		per_center += n.pos
		per_vel += n.vel
		if dist < DESIRED_SEPARATION_SQRT {
			sep_vel += Vector3Normalize(b.pos - n.pos) / dist
		}
	}
	if neighbors > 0 {
		per_center /= neighbors
		per_vel /= neighbors
		sep_vel /= neighbors
	}

	coh_vel := Vector3Normalize(per_center - b.pos) * MAX_SPEED
	ali_vel := Vector3Normalize(per_vel) * MAX_SPEED
	sep_vel = Vector3Normalize(sep_vel) * MAX_SPEED

	acc: Vector3
	if coh_vel != 0 {
		acc += Vector3ClampValue(coh_vel - b.vel, -MAX_FORCE, MAX_FORCE) * COH_WEIGHT
	}
	if ali_vel != 0 {
		acc += Vector3ClampValue(ali_vel - b.vel, -MAX_FORCE, MAX_FORCE) * ALI_WEIGHT
	}
	if sep_vel != 0 {
		acc += Vector3ClampValue(sep_vel - b.vel, -MAX_FORCE, MAX_FORCE) * SEP_WEIGHT
	}

	vel = Vector3ClampValue(b.vel + acc, -MAX_SPEED, MAX_SPEED)
	pos = b.pos + b.vel * delta
	return
}

// MARK: boid_wrap_pos
boid_wrap_pos :: proc(in_pos: rl.Vector3) -> (pos: rl.Vector3) {
	origin := rl.Vector3{0, 0, 0}
	HI := GAME_VOLUME_A
	LOW := GAME_VOLUME_B

	if in_pos.x > HI.x ||
	   in_pos.y > HI.y ||
	   in_pos.z > HI.z ||
	   in_pos.x < LOW.x ||
	   in_pos.y < LOW.y ||
	   in_pos.z < LOW.z {
		return rl.Vector3Clamp(origin - in_pos, LOW, HI)
	}

	return in_pos
}

// MARK: move_boids
move_boids :: proc() {
	delta := rl.GetFrameTime()

	for &b in state.boids {
		pos, vel := boid_apply_forces(b, delta)
		b.pos = boid_wrap_pos(pos)
		b.vel = vel
	}
}

@(export)
game_loop :: proc() -> bool {
	// MARK: Update

	if rl.IsKeyPressed(.R) {
		create_boids(&state^)
	}

	// move_boids()

	rl.UpdateCamera(&state.camera, .ORBITAL)
	rl.SetShaderValue(
		state.cube_mat.shader,
		state.cube_mat.shader.locs[rl.ShaderLocationIndex.VECTOR_VIEW],
		&state.camera.position,
		.VEC3,
	)

	// MARK: Draw
	rl.BeginDrawing()

	rl.ClearBackground(rl.RAYWHITE)
	rl.DrawFPS(10, 10)
	rl.DrawText("r - reset", 10, rl.GetScreenHeight() - 20, 10, rl.RAYWHITE)

	rl.BeginMode3D(state.camera)
	// rl.DrawSphere(0, 20, {230, 41, 55, 128})

	rl.DrawCubeWiresV(0, GAME_VOLUME_A - GAME_VOLUME_B, rl.GRAY)
	// rl.DrawGrid(20, 10)

	matrices := make([dynamic]rl.Matrix, len(state.boids))
	for b, i in state.boids {
		SCALE :: 5

		rotation_q := rl.QuaternionFromVector3ToVector3({0, 0, 1}, b.vel)
		m :=
			rl.MatrixTranslate(b.pos.x, b.pos.y, b.pos.z) *
			rl.QuaternionToMatrix(rotation_q) *
			rl.MatrixScale(SCALE, SCALE, SCALE)

		matrices[i] = m
		// append(&matrices, m)
		// rl.DrawMesh(state.boid_model.meshes[0], state.boid_model.materials[1], m)
		// draw_model_mesh(state.boid_model, 0, m)
		// rl.DrawMesh(state.cube, state.cube_mat, m)
	}

	// rl.DrawMeshInstanced(
	// 	state.boid_model.meshes[0],
	// 	state.boid_model.materials[1],
	// 	raw_data(matrices),
	// 	cast(i32)len(matrices),
	// )

	// for m in state.boid_transforms {
	// 	// rl.DrawMesh(state.cube, state.cube_mat_def, m)
	// 	rl.DrawMesh(state.boid_model.meshes[0], state.boid_model.materials[1], m)
	// }


	// rl.DrawMesh(
	// 	state.cube,
	// 	state.cube_mat_def,
	// 	rl.MatrixTranslate(-10, 0, 0) * rl.MatrixScale(20, 20, 20),
	// )

	rl.DrawMeshInstanced(
		state.cube,
		state.cube_mat,
		raw_data(matrices),
		i32(len(state.boids)),
	)

	// rl.DrawMesh(
	// 	state.cube,
	// 	state.cube_mat_def,
	// 	rl.MatrixTranslate(10, 0, 0) * rl.MatrixScale(20, 20, 20),
	// )

	rl.EndMode3D()

	rl.EndDrawing()

	delete(matrices)

	return !rl.WindowShouldClose()
}

@(export)
game_shutdown :: proc() {
	log.debug("shutdown")

	game_memory_cleanup(state)
	rl.CloseWindow()
}
@(export)
game_memory_size :: proc() -> int {return size_of(Game_State)}
@(export)
game_memory_set :: proc(mem: rawptr) {state = (^Game_State)(mem)}
@(export)
game_force_reload :: proc() -> bool {return rl.IsKeyPressed(.F6)}
