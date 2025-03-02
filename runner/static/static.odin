package runner_static

import game "../../source"

main :: proc() {
	game.game_window_init()
	game.game_memory_set(game.game_memory_init())

	for game.game_loop() {
		free_all(context.temp_allocator)
	}

	game.game_shutdown()
}
