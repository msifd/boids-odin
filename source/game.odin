package arcadia

import rl "vendor:raylib"

WINDOW_WIDHT :: 854
WINDOW_HEIGHT :: 480

Boid :: struct {
	pos: rl.Vector2,
	vel: rl.Vector2,
	acc: rl.Vector2,
}

Game_State :: struct {
	boids: [dynamic]Boid,
}

state: ^Game_State

@(export)
game_window_init :: proc() {
	rl.SetConfigFlags({.VSYNC_HINT})
	rl.InitWindow(WINDOW_WIDHT, WINDOW_HEIGHT, "Boids")
	rl.SetTargetFPS(rl.GetMonitorRefreshRate(rl.GetCurrentMonitor()) + 1)
}

@(export)
game_memory_make :: proc() -> rawptr {
	s := new(Game_State)
	create_boids(s)
	return s
}

create_boids :: proc(s: ^Game_State) {
	clear(&s.boids)

	for _ in 0 ..< 500 {
		x := cast(f32)rl.GetRandomValue(10, WINDOW_WIDHT - 10)
		y := cast(f32)rl.GetRandomValue(10, WINDOW_HEIGHT - 10)
		vx := cast(f32)rl.GetRandomValue(-10, 10) / 10
		vy := cast(f32)rl.GetRandomValue(-10, 10) / 10

		append(&s.boids, Boid{pos = {x, y}, vel = {vx, vy}})
	}
}

move_boids :: proc() {
	EFFECT_RADIUS :: 50
	DESIRED_SEPARATION :: 25
	MAX_SPEED :: 150.
	MAX_FORCE :: 2

	COH_WEIGHT :: 1.
	ALI_WEIGHT :: 1.
	SEP_WEIGHT :: 1.5
	CUR_WEIGHT :: 1

	delta := rl.GetFrameTime()

	for &b in state.boids {
		neighbors: f32
		per_center: rl.Vector2
		per_vel: rl.Vector2
		sep_vel: rl.Vector2

		for n in state.boids {
			dist := rl.Vector2Distance(b.pos, n.pos)
			if dist == 0 || dist > EFFECT_RADIUS {
				continue
			}

			neighbors += 1
			per_center += n.pos
			per_vel += n.vel
			if dist < DESIRED_SEPARATION {
				sep_vel += rl.Vector2Normalize(b.pos - n.pos) / dist
			}
		}
		if neighbors > 0 {
			per_center /= neighbors
			per_vel /= neighbors
			sep_vel /= neighbors
		}

		coh_vel := rl.Vector2Normalize(per_center - b.pos) * MAX_SPEED
		ali_vel := rl.Vector2Normalize(per_vel) * MAX_SPEED
		sep_vel = rl.Vector2Normalize(sep_vel) * MAX_SPEED

		acc: rl.Vector2
		if rl.IsMouseButtonDown(.LEFT) {
			cur := rl.GetMousePosition()
			cur_vel := rl.Vector2Normalize(cur - b.pos) * MAX_SPEED
			acc += rl.Vector2ClampValue(cur_vel - b.vel, -MAX_FORCE, MAX_FORCE) * CUR_WEIGHT
		}
		if coh_vel != 0 {
			acc += rl.Vector2ClampValue(coh_vel - b.vel, -MAX_FORCE, MAX_FORCE) * COH_WEIGHT
		}
		if ali_vel != 0 {
			acc += rl.Vector2ClampValue(ali_vel - b.vel, -MAX_FORCE, MAX_FORCE) * ALI_WEIGHT
		}
		if sep_vel != 0 {
			acc += rl.Vector2ClampValue(sep_vel - b.vel, -MAX_FORCE, MAX_FORCE) * SEP_WEIGHT
		}

		b.vel = rl.Vector2ClampValue(b.vel + acc, -MAX_SPEED, MAX_SPEED)
		b.pos += b.vel * delta
		b.acc = acc
	}
}

wrap_around :: proc() {
	HALF :: 10

	for &b in state.boids {
		if b.pos.x < -HALF {
			b.pos.x = WINDOW_WIDHT + HALF
		}
		if b.pos.y < -HALF {
			b.pos.y = WINDOW_HEIGHT + HALF
		}
		if b.pos.x > WINDOW_WIDHT + HALF {
			b.pos.x = -HALF
		}
		if b.pos.y > WINDOW_HEIGHT + HALF {
			b.pos.y = -HALF
		}
	}
}

@(export)
game_loop :: proc() -> bool {
	if rl.IsKeyPressed(.R) {
		create_boids(&state^)
	}

	rl.BeginDrawing()

	rl.ClearBackground(rl.BLACK)
	// rl.DrawFPS(10, 10)
	rl.DrawText("r - reset", 10, 10, 10, rl.RAYWHITE)

	move_boids()
	wrap_around()
	for b in state.boids {
		RADIUS :: 5
		rl.DrawCircleV(b.pos, RADIUS, rl.RED)
		rl.DrawLineV(b.pos, b.pos + rl.Vector2Normalize(b.vel) * 10, rl.RED)
	}

	rl.EndDrawing()

	return !rl.WindowShouldClose()
}

@(export)
game_shutdown :: proc() {
	rl.CloseWindow()
}
@(export)
game_memory_size :: proc() -> int {return size_of(Game_State)}
@(export)
game_memory_set :: proc(mem: rawptr) {state = (^Game_State)(mem)}
@(export)
game_force_reload :: proc() -> bool {return rl.IsKeyPressed(.F6)}
