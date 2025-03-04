package boids

import "core:log"
import "core:mem"
import rl "vendor:raylib"

RES_BOID :: #load("../assets/boid.glb")

Shader_Type :: enum {
	BASIC_INSTANCING_VERT,
	BASIC_FRAG,
}
SHADERS :: [Shader_Type]cstring {
	.BASIC_INSTANCING_VERT = #load("../assets/basic_instancing.vs", cstring),
	.BASIC_FRAG            = #load("../assets/basic.fs", cstring),
}

VOLUME_SIZE :: 100

Boid :: struct {
	pos: rl.Vector3,
	vel: rl.Vector3,
}

Game_State :: struct {
	boid_model: rl.Model,
	camera:     rl.Camera3D,
	boids:      [dynamic]Boid,
	// boid_transforms: [dynamic]rl.Matrix,
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
	data_copy := rl.MemAlloc(u32(len))
	mem.copy(data_copy, raw_data(orig_data), len)
	data_len^ = i32(len)
	ptr := cast([^]u8)data_copy
	return ptr
}

// MARK: game mem init
@(export)
game_memory_init :: proc() -> rawptr {
	rl.SetLoadFileDataCallback(load_raylib_file)

	s := new(Game_State)

	instancing_shader := rl.LoadShaderFromMemory(
		SHADERS[.BASIC_INSTANCING_VERT],
		SHADERS[.BASIC_FRAG],
	)
	instancing_shader.locs[rl.ShaderLocationIndex.MATRIX_MVP] = rl.GetShaderLocation(
		instancing_shader,
		"mvp",
	)
	instancing_shader.locs[rl.ShaderLocationIndex.MATRIX_MODEL] = rl.GetShaderLocationAttrib(
		instancing_shader,
		"instanceTransform",
	)

	model := rl.LoadModel("boid.glb")
	model.materials[1].shader = instancing_shader
	model.materials[1].maps[rl.MaterialMapIndex.ALBEDO].color = rl.BLUE
	s.boid_model = model

	s.camera = rl.Camera3D {
		position   = {100, 50, 200},
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
}

// MARK: create_boids
create_boids :: proc(s: ^Game_State) {
	clear_dynamic_array(&s.boids)
	// clear_dynamic_array(&s.boid_transforms)

	BOIDS_COUNT :: 1000
	reserve_dynamic_array(&s.boids, BOIDS_COUNT)
	// reserve_dynamic_array(&s.boid_transforms, BOIDS_COUNT)

	PREC :: 10
	SVS :: VOLUME_SIZE * PREC

	SCALE :: 8
	scale_mx := rl.MatrixScale(SCALE, SCALE, SCALE)

	for _ in 0 ..< BOIDS_COUNT {
		pos := rl.Vector3 {
			f32(rl.GetRandomValue(-SVS, SVS)),
			f32(rl.GetRandomValue(-SVS, SVS)),
			f32(rl.GetRandomValue(-SVS, SVS)),
		}
		pos /= PREC

		append(&s.boids, Boid{pos, 0})
	}
}

// MARK: boid_apply_forces
boid_apply_forces :: proc(b: Boid, delta: f32) -> (pos: rl.Vector3, vel: rl.Vector3) {
	using rl

	EFFECT_RADIUS_SQRT :: 20 * 20
	DESIRED_SEPARATION_SQRT :: 8 * 8
	MAX_SPEED :: 80
	MAX_FORCE :: 1

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
	if coh_vel != 0 do acc += Vector3ClampValue(coh_vel - b.vel, -MAX_FORCE, MAX_FORCE) * COH_WEIGHT
	if ali_vel != 0 do acc += Vector3ClampValue(ali_vel - b.vel, -MAX_FORCE, MAX_FORCE) * ALI_WEIGHT
	if sep_vel != 0 do acc += Vector3ClampValue(sep_vel - b.vel, -MAX_FORCE, MAX_FORCE) * SEP_WEIGHT

	vel = Vector3ClampValue(b.vel + acc, -MAX_SPEED, MAX_SPEED)
	pos = b.pos + b.vel * delta
	return
}

// MARK: boid_wrap_pos
boid_wrap_pos :: proc(in_pos: rl.Vector3) -> (pos: rl.Vector3) {
	HI :: VOLUME_SIZE
	LOW :: -VOLUME_SIZE

	if in_pos.x > HI ||
	   in_pos.y > HI ||
	   in_pos.z > HI ||
	   in_pos.x < LOW ||
	   in_pos.y < LOW ||
	   in_pos.z < LOW {
		return rl.Vector3Clamp(-in_pos, LOW, HI)
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
	if rl.IsMouseButtonPressed(.LEFT) {
		if rl.IsCursorHidden() {
			rl.ShowCursor()
			rl.EnableCursor()
		} else {
			rl.HideCursor()
			rl.DisableCursor()
		}
	}

	move_boids()

	rl.UpdateCamera(&state.camera, .THIRD_PERSON)

	// MARK: Draw 

	rl.BeginDrawing()

	rl.ClearBackground(rl.BLACK)
	rl.DrawFPS(10, 10)
	rl.DrawText("r - reset", 10, rl.GetScreenHeight() - 20, 10, rl.RAYWHITE)
	rl.BeginMode3D(state.camera)

	rl.DrawCubeWiresV(0, VOLUME_SIZE * 2, rl.GRAY)
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
	}

	rl.DrawMeshInstanced(
		state.boid_model.meshes[0],
		state.boid_model.materials[1],
		raw_data(matrices),
		i32(len(state.boids)),
	)

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
