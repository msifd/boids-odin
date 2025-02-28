package arcadia

import "core:log"
import "core:strings"
import rl "vendor:raylib"

WINDOW_WIDHT :: 854
WINDOW_HEIGHT :: 480
GAME_VOLUME_A :: rl.Vector3{100, 100, 100}
GAME_VOLUME_B :: rl.Vector3{-100, -100, -100}

Boid :: struct {
	pos: rl.Vector3,
	vel: rl.Vector3,
}

Game_State :: struct {
	boid_model:      rl.Model,
	camera:          rl.Camera3D,
	boids:           [dynamic]Boid,
	boid_transforms: [dynamic]rl.Matrix,
}

state: ^Game_State

@(export)
game_window_init :: proc() {
	rl.SetConfigFlags({.VSYNC_HINT})
	rl.InitWindow(WINDOW_WIDHT, WINDOW_HEIGHT, "Boids")
	rl.SetTargetFPS(rl.GetMonitorRefreshRate(rl.GetCurrentMonitor()) + 1)
}

// MARK: game_memory_make
@(export)
game_memory_make :: proc() -> rawptr {
	s := new(Game_State)

	s.boid_model = rl.LoadModel("assets/boid.glb")
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
	clear_dynamic_array(&s.boid_transforms)
	delete(s.boids)
	delete(s.boid_transforms)

	rl.UnloadModel(s.boid_model)
}

create_boids :: proc(s: ^Game_State) {
	clear_dynamic_array(&s.boids)
	clear_dynamic_array(&s.boid_transforms)

	BOIDS_COUNT :: 800
	reserve_dynamic_array(&s.boids, BOIDS_COUNT)
	reserve_dynamic_array(&s.boid_transforms, BOIDS_COUNT)

	PREC :: 10
	GVA: [3]i32 = {cast(i32)GAME_VOLUME_A.x, cast(i32)GAME_VOLUME_A.y, cast(i32)GAME_VOLUME_A.z}
	GVB: [3]i32 = {cast(i32)GAME_VOLUME_B.x, cast(i32)GAME_VOLUME_B.y, cast(i32)GAME_VOLUME_B.z}
	GVA = GVA * PREC - PREC
	GVB = GVB * PREC + PREC

	SCALE :: 8
	scale_mx := rl.MatrixScale(SCALE, SCALE, SCALE)

	for _ in 0 ..< BOIDS_COUNT {
		pos := rl.Vector3 {
			cast(f32)rl.GetRandomValue(GVB.x, GVA.x),
			cast(f32)rl.GetRandomValue(GVB.y, GVA.y),
			cast(f32)rl.GetRandomValue(GVB.z, GVA.z),
		}
		pos /= PREC
		vel := rl.Vector3 {
			cast(f32)rl.GetRandomValue(-10, 10) / 5,
			cast(f32)rl.GetRandomValue(-10, 10) / 5,
			cast(f32)rl.GetRandomValue(-10, 10) / 5,
		}

		append(&s.boids, Boid{pos, vel})
	}
}

// MARK: boid_apply_forces
boid_apply_forces :: proc(b: ^Boid, delta: f32) {
	using rl

	EFFECT_RADIUS :: 25
	DESIRED_SEPARATION :: 8
	MAX_SPEED :: 50.
	MAX_FORCE :: 0.5

	COH_WEIGHT :: 1.
	ALI_WEIGHT :: 1.
	SEP_WEIGHT :: 1.5
	CUR_WEIGHT :: 1

	neighbors: f32
	per_center: Vector3
	per_vel: Vector3
	sep_vel: Vector3

	for n in state.boids {
		dist := Vector3Distance(b.pos, n.pos)
		if dist == 0 || dist > EFFECT_RADIUS {
			continue
		}

		neighbors += 1
		per_center += n.pos
		per_vel += n.vel
		if dist < DESIRED_SEPARATION {
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

	b.vel = Vector3ClampValue(b.vel + acc, -MAX_SPEED, MAX_SPEED)
	b.pos += b.vel * delta
}

// MARK: boid_wrap_pos
boid_wrap_pos :: proc(b: ^Boid) {
	OFF :: 10
	HI := GAME_VOLUME_A + OFF
	LOW := GAME_VOLUME_B - OFF

	if b.pos.x > HI.x {
		b.pos.x = LOW.x + OFF
	}
	if b.pos.y > HI.y {
		b.pos.y = LOW.y + OFF
	}
	if b.pos.z > HI.z {
		b.pos.z = LOW.z + OFF
	}

	if b.pos.x < LOW.x {
		b.pos.x = HI.x - OFF
	}
	if b.pos.y < LOW.y {
		b.pos.y = HI.y - OFF
	}
	if b.pos.z < LOW.z {
		b.pos.z = HI.z - OFF
	}
}

// MARK: move_boids
move_boids :: proc() {
	delta := rl.GetFrameTime()

	for &b in state.boids {
		boid_apply_forces(&b, delta)
		boid_wrap_pos(&b)
	}
}

@(export)
game_loop :: proc() -> bool {
	// MARK: Update
	// rl.UpdateCamera(&state.camera, .ORBITAL)

	if rl.IsKeyPressed(.R) {
		create_boids(&state^)
	}

	move_boids()

	// for b, i in state.boids {

	// }

	// MARK: Draw
	rl.BeginDrawing()

	rl.ClearBackground(rl.BLACK)
	// rl.DrawFPS(10, 10)
	rl.DrawText("r - reset", 10, 10, 10, rl.RAYWHITE)

	rl.BeginMode3D(state.camera)
	// rl.DrawSphere(0, 20, {230, 41, 55, 128})

	for b in state.boids {
		SCALE :: 8

		rotation_q := rl.QuaternionFromVector3ToVector3({0, 0, 1}, b.vel)
		m :=
			rl.MatrixTranslate(b.pos.x, b.pos.y, b.pos.z) *
			rl.QuaternionToMatrix(rotation_q) *
			rl.MatrixScale(SCALE, SCALE, SCALE)

		rl.DrawMesh(state.boid_model.meshes[0], state.boid_model.materials[0], m)
	}
	// rl.DrawMeshInstanced()

	rl.DrawGrid(20, 10)

	rl.EndMode3D()

	rl.EndDrawing()

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
