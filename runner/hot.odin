package runner_hot

import "core:dynlib"
import "core:fmt"
import "core:log"
import "core:os/os2"
import "core:path/filepath"
import "core:time"

Game_API :: struct {
	__handle: dynlib.Library,
	__is_odd: bool,
	init:     proc(),
	loop:     proc() -> bool,
	shutdown: proc(),
}

load_dll :: proc(path: string, is_odd: bool) -> (api: Game_API, ok: bool) {
	log.info("Load DLL at", path, is_odd)

	oddity_str := "A" if is_odd else "B"
	tmp_filename := fmt.tprintf("tmp%v_game.dll", oddity_str)
	tmp_path := filepath.join({filepath.dir(path), tmp_filename})

	log.debug("Copy DLL to", tmp_path)
	os2.copy_file(tmp_path, path)

	_, ok = dynlib.initialize_symbols(&api, tmp_path, "game_")

	api.__is_odd = is_odd

	return
}

get_file_timestamp :: proc(path: string) -> time.Time {
	timestamp, err := os2.last_write_time_by_name(path)
	if err != nil {
		log.error("last_write_time error:", os2.error_string(err))
		os2.exit(-1)
	}
	return timestamp
}

main :: proc() {
	logger := log.create_console_logger()
	context.logger = logger

	{
		cwd, err := os2.get_working_directory(context.allocator)
		if err != nil {
			log.error("CWD error:", dynlib.last_error())
			os2.exit(-1)
		}
	}

	assert(len(os2.args) >= 2, "Missing DLL arg")
	dll_path := os2.args[1]
	log.info("DLL:", dll_path)

	api, ok := load_dll(dll_path, false)
	if !ok {
		log.error("DLL load failed! Error:", dynlib.last_error())
		os2.exit(-1)
	}

	dll_last_check := time.now()
	dll_reload_period := time.Second
	dll_last_timestamp := get_file_timestamp(dll_path)

	api.init()
	for api.loop() {
		if time.since(dll_last_check) > dll_reload_period {
			dll_last_check = time.now()
			log.info("check dll", time.to_unix_nanoseconds(time.now()))

			dll_current_timestamp := get_file_timestamp(dll_path)
			if dll_current_timestamp == dll_last_timestamp {
				continue
			}

			dll_last_timestamp = dll_current_timestamp
			new_api, ok := load_dll(dll_path, !api.__is_odd)
			if !ok {
				log.warn("DLL load error:", dynlib.last_error())
				continue
			}

			is_unloaded := dynlib.unload_library(api.__handle)
			if !is_unloaded {
				log.warn("DLL unload error:", dynlib.last_error())
				dynlib.unload_library(new_api.__handle)

				continue
			}

			api = new_api
			log.info("Hot reloaded")
		}
	}
	api.shutdown()
}
