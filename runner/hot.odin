package runner_hot

import "core:dynlib"
import "core:log"
import "core:os"
import "core:os/os2"
import "core:path/filepath"
import "core:time"

Game_API :: struct {
	__handle: dynlib.Library,
	init:     proc(),
	loop:     proc() -> bool,
	shutdown: proc(),
}

load_dll :: proc(path: string) -> (api: Game_API, ok: bool) {
	// os2.copy_file()

	log.info("Load DLL at", path)
	_, ok = dynlib.initialize_symbols(&api, path, "game_")

	return
}

main :: proc() {
	logger := log.create_console_logger()
	context.logger = logger

	log.info("CWD:", os.get_current_directory())

	assert(len(os.args) >= 2, "Missing DLL arg")
	dll_path := os.args[1]
	log.info("DLL:", dll_path)

	api, ok := load_dll(dll_path)
	if !ok {
		log.error("DLL load failed! Error:", dynlib.last_error())
		os.exit(-1)
	}

	dll_last_check := time.now()
	dll_reload_period := time.Second

	api.init()
	for api.loop() {
		if time.since(dll_last_check) > dll_reload_period {
			dll_last_check = time.now()
			log.info("check dll", time.to_unix_nanoseconds(time.now()))

			dll_time, err := os.last_write_time_by_name(dll_path)
			assert(err == nil)

		}
	}
	api.shutdown()
}
