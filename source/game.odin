package arcadia

import rl "vendor:raylib"

main :: proc() {
    WINDOW_WIDHT :: 854
    WINDOW_HEIGHT :: 480

    rl.InitWindow(WINDOW_WIDHT, WINDOW_HEIGHT, "Arcadia")
    rl.SetTargetFPS(144)

    for !rl.WindowShouldClose() {
        rl.BeginDrawing()
        
        rl.ClearBackground(rl.RAYWHITE)
        rl.DrawFPS(10, 10)
        rl.DrawText("Hello Arcadia!", 360, WINDOW_HEIGHT /  2, 20, rl.LIGHTGRAY)

        rl.EndDrawing()
    }

    rl.CloseWindow()
}