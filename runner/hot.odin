package runner_hot

import "core:dynlib"
import "core:fmt"
import "core:log"
import "core:os/os2"
import "core:path/filepath"
import "core:time"

Game_Lib :: struct {
	__handle:    dynlib.Library,
	__path:      string,
	window_init: proc(),
	loop:        proc() -> bool,
	shutdown:    proc(),
	memory_init: proc() -> rawptr,
	memory_size: proc() -> int,
	memory_set:  proc(mem: rawptr),
}

load_lib :: proc(path: string, index: int) -> (lib: Game_Lib, ok: bool) {
	log.info("Load DLL at", path, index)

	tmp_filename := fmt.tprintf("tmp%v_%v", index, filepath.base(path))
	tmp_path := filepath.join({filepath.dir(path), tmp_filename})

	log.info("Copy DLL to", tmp_path)
	err := os2.copy_file(tmp_path, path)
	if err != nil {return}
	lib.__path = tmp_path

	_, ok = dynlib.initialize_symbols(&lib, tmp_path, "game_")

	return
}

unload_lib :: proc(lib: ^Game_Lib) {
	log.info("Unload lib", lib.__path)

	ok := dynlib.unload_library(lib.__handle)
	if !ok {
		log.error("unload failed:", dynlib.last_error())
		return
	}

	os2.remove(lib.__path)
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

	lib, ok := load_lib(dll_path, 0)
	if !ok {
		log.error("DLL load failed! Error:", dynlib.last_error())
		os2.exit(-1)
	}

	lib_counter := 0
	old_game_libs := make([dynamic]Game_Lib)

	dll_last_check := time.now()
	dll_reload_period := time.Second
	dll_last_timestamp := get_file_timestamp(dll_path)

	lib.window_init()
	mem_ptr := lib.memory_init()
	mem_size := lib.memory_size()

	for lib.loop() {
		if time.since(dll_last_check) > dll_reload_period {
			dll_last_check = time.now()
			log.debug("check dll", time.to_unix_nanoseconds(time.now()))

			dll_current_timestamp := get_file_timestamp(dll_path)
			if dll_current_timestamp == dll_last_timestamp {
				continue
			}

			dll_last_timestamp = dll_current_timestamp
			lib_counter += 1

			new_lib, ok := load_lib(dll_path, lib_counter)
			if !ok {
				log.error("DLL load error:", dynlib.last_error())
				continue
			}

			append(&old_game_libs, lib)

			new_mem_size := new_lib.memory_size()

			if new_mem_size == mem_size {
				new_lib.memory_set(mem_ptr)
			} else {
				log.info("Reset memory")
				for &l in old_game_libs {unload_lib(&l)}
				clear(&old_game_libs)

				free(mem_ptr)
				mem_ptr = new_lib.memory_init()
				mem_size = new_mem_size
			}

			lib = new_lib
			log.info("Hot reloaded")
		}
	}

	lib.shutdown()

	for &l in old_game_libs {unload_lib(&l)}
	clear(&old_game_libs)
	unload_lib(&lib)
}
