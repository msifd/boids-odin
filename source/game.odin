package arcadia

import rl "vendor:raylib"

WINDOW_WIDHT :: 854
WINDOW_HEIGHT :: 480

@(export)
game_init :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(WINDOW_WIDHT, WINDOW_HEIGHT, "Arcadia")
}

@(export)
game_loop :: proc() -> bool {
	rl.BeginDrawing()

	rl.ClearBackground(rl.RAYWHITE)
	rl.DrawFPS(10, 10)
	rl.DrawText("Hello Arcadia!", 360, WINDOW_HEIGHT / 2, 20, rl.LIGHTGRAY)

	rl.EndDrawing()

	return !rl.WindowShouldClose()
}

@(export)
game_shutdown :: proc() {
	rl.CloseWindow()
}
