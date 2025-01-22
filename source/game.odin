package arcadia

import "core:fmt"
import rl "vendor:raylib"

WINDOW_WIDHT :: 854
WINDOW_HEIGHT :: 480

Game_State :: struct {
	counter: int,
}

state: ^Game_State

@(export)
game_window_init :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(WINDOW_WIDHT, WINDOW_HEIGHT, "Arcadia")
}

@(export)
game_memory_init :: proc() -> rawptr {
	state = new(Game_State)
	return state
}

@(export)
game_loop :: proc() -> bool {
	state.counter += 1

	rl.BeginDrawing()

	rl.ClearBackground(rl.RAYWHITE)
	rl.DrawFPS(10, 10)
	rl.DrawText("Hello Arcadia!", 360, 200, 20, rl.LIGHTGRAY)
	rl.DrawText(fmt.ctprintf("Counter: %v", state.counter), 360, 216, 20, rl.BEIGE)

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
