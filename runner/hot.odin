package runner_hot

import "core:dynlib"
import "core:fmt"
import "core:log"
import "core:os/os2"
import "core:path/filepath"
import "core:time"

Game_Lib :: struct {
	__handle:     dynlib.Library,
	__path:       string,
	window_init:  proc(),
	loop:         proc() -> bool,
	shutdown:     proc(),
	memory_make:  proc() -> rawptr,
	memory_size:  proc() -> int,
	memory_set:   proc(mem: rawptr),
	force_reload: proc() -> bool,
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
	dll_reload_period :: 1000 * time.Millisecond
	dll_last_timestamp := get_file_timestamp(dll_path)

	lib.window_init()
	mem_ptr := lib.memory_make()
	mem_size := lib.memory_size()
	lib.memory_set(mem_ptr)

	for lib.loop() {
		force_reload := lib.force_reload()
		should_check_dll := time.since(dll_last_check) > dll_reload_period

		if should_check_dll || force_reload {
			dll_last_check = time.now()

			dll_current_timestamp := get_file_timestamp(dll_path)
			dll_changed: bool = dll_current_timestamp != dll_last_timestamp
			if !dll_changed && !force_reload {
				continue
			}

			target_lib := lib
			if dll_changed {
				dll_last_timestamp = dll_current_timestamp
				lib_counter += 1

				new_lib, ok := load_lib(dll_path, lib_counter)
				if !ok {
					log.error("DLL load error:", dynlib.last_error())
					continue
				}

				append(&old_game_libs, new_lib)
				target_lib = new_lib
			}

			new_mem_size := target_lib.memory_size()
			mem_changed := new_mem_size != mem_size

			if mem_changed || force_reload {
				if dll_changed {
					log.info("Unload old libs")
					for &l in old_game_libs {unload_lib(&l)}
					clear(&old_game_libs)
				}

				log.info("Reset memory")
				free(mem_ptr)
				mem_ptr = target_lib.memory_make()
				mem_size = new_mem_size
			}
			target_lib.memory_set(mem_ptr)

			lib = target_lib
			log.info("Hot reloaded")
		}

		free_all(context.temp_allocator)
	}

	lib.shutdown()

	for &l in old_game_libs {unload_lib(&l)}
	clear(&old_game_libs)
	unload_lib(&lib)
}
