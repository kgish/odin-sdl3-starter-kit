// Lifecycle integration runner.
//
// Launches the real starter executable (startup adapter, SDL callbacks and
// all) once per case with SDL's dummy drivers, so SDL's main-thread
// requirements are met by the child process rather than a test worker thread.
//
// Usage: integration <starter-exe> <log-dir> [--release]
//   --release  the executable logs at Info level, so skip checks that rely on
//              its Debug resource-destruction lines.
package integration

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"

TIMEOUT :: 30 * time.Second

Expect :: struct {
	exit_code:  int,
	contains:   []string,
	excludes:   []string,
	// Exact occurrence counts; only checked for debug executables.
	counts:     []Count,
}

Count :: struct {
	text: string,
	n:    int,
}

Case :: struct {
	name:   string,
	args:   []string,
	expect: Expect,
}

DESTROYED_BOTH :: []Count{{"destroyed renderer", 1}, {"destroyed window", 1}}
DESTROYED_WINDOW :: []Count{{"destroyed renderer", 0}, {"destroyed window", 1}}
DESTROYED_NONE :: []Count{{"destroyed renderer", 0}, {"destroyed window", 0}}

CASES := []Case{
	{
		"smoke", {"--frames=60"},
		{0, {"initialized", "smoke run complete after 60 frames", "quit: SUCCESS"}, nil, DESTROYED_BOTH},
	},
	{
		"smoke-no-vsync", {"--frames=30", "--no-vsync"},
		{0, {"Hz callback rate", "quit: SUCCESS"}, nil, DESTROYED_BOTH},
	},
	{
		"quit-event", {"--push-quit-at=3", "--frames=600"},
		{0, {"quit requested", "quit: SUCCESS"}, {"smoke run complete"}, DESTROYED_BOTH},
	},
	{
		"missing-assets", {"--frames=5", "--assets=__missing_asset_dir__"},
		{0, {"asset directory not found: __missing_asset_dir__", "quit: SUCCESS"}, nil, DESTROYED_BOTH},
	},
	{
		"bad-option", {"--definitely-not-an-option"},
		{1, {"invalid configuration (Unknown_Option)", "quit: FAILURE"}, {"initialized"}, DESTROYED_NONE},
	},
	{
		"fail-after-metadata", {"--fail-after=metadata"},
		{1, {"injected failure after stage Metadata", "quit: FAILURE"}, nil, DESTROYED_NONE},
	},
	{
		"fail-after-video", {"--fail-after=video"},
		{1, {"injected failure after stage Video", "quit: FAILURE"}, nil, DESTROYED_NONE},
	},
	{
		"fail-after-window", {"--fail-after=window"},
		{1, {"injected failure after stage Window", "quit: FAILURE"}, nil, DESTROYED_WINDOW},
	},
	{
		"fail-after-renderer", {"--fail-after=renderer"},
		{1, {"injected failure after stage Renderer", "quit: FAILURE"}, nil, DESTROYED_BOTH},
	},
	{
		"fail-after-game", {"--fail-after=game"},
		{1, {"injected failure after stage Game", "quit: FAILURE"}, {"initialized"}, DESTROYED_BOTH},
	},
}

main :: proc() {
	if len(os.args) < 3 {
		fmt.eprintln("usage: integration <starter-exe> <log-dir> [--release]")
		os.exit(2)
	}
	exe := os.args[1]
	log_dir := os.args[2]
	release := len(os.args) > 3 && os.args[3] == "--release"

	if err := os.make_directory_all(log_dir); err != nil && !os.is_dir(log_dir) {
		fmt.eprintfln("cannot create %s: %v", log_dir, err)
		os.exit(2)
	}

	env := headless_env()
	failed := 0
	for c in CASES {
		problems := run_case(exe, log_dir, env, c, release)
		if len(problems) == 0 {
			fmt.printfln("PASS %s", c.name)
		} else {
			failed += 1
			fmt.printfln("FAIL %s", c.name)
			for p in problems {
				fmt.printfln("     %s", p)
			}
		}
		free_all(context.temp_allocator)
	}

	fmt.printfln("%d/%d cases passed", len(CASES) - failed, len(CASES))
	os.exit(1 if failed > 0 else 0)
}

headless_env :: proc() -> []string {
	inherited, _ := os.environ(context.allocator)
	env := make([dynamic]string, 0, len(inherited) + 3)
	for kv in inherited {
		if strings.has_prefix(kv, "SDL_VIDEO_DRIVER=") || strings.has_prefix(kv, "SDL_RENDER_DRIVER=") || strings.has_prefix(kv, "SDL_AUDIO_DRIVER=") {
			continue
		}
		append(&env, kv)
	}
	append(&env, "SDL_VIDEO_DRIVER=dummy", "SDL_RENDER_DRIVER=software", "SDL_AUDIO_DRIVER=dummy")
	return env[:]
}

// Runs one case and returns a list of human-readable problems (empty = pass).
run_case :: proc(exe, log_dir: string, env: []string, c: Case, release: bool) -> []string {
	problems := make([dynamic]string, context.temp_allocator)

	log_path := filepath.join({log_dir, fmt.tprintf("%s.log", c.name)}, context.temp_allocator) or_else ""
	out, create_err := os.create(log_path)
	if create_err != nil {
		append(&problems, fmt.tprintf("cannot create %s: %v", log_path, create_err))
		return problems[:]
	}

	command := make([dynamic]string, context.temp_allocator)
	append(&command, exe)
	append(&command, ..c.args)

	// Run from the log directory: the app must not depend on the working directory.
	process, start_err := os.process_start({working_dir = log_dir, command = command[:], env = env, stdout = out, stderr = out})
	if start_err != nil {
		os.close(out)
		append(&problems, fmt.tprintf("cannot start %s: %v", exe, start_err))
		return problems[:]
	}

	state, wait_err := os.process_wait(process, TIMEOUT)
	if wait_err != nil {
		_ = os.process_kill(process)
		_, _ = os.process_wait(process)
		append(&problems, fmt.tprintf("did not exit within %v (%v)", TIMEOUT, wait_err))
	}
	os.close(out)

	data, _ := os.read_entire_file(log_path, context.temp_allocator)
	output := string(data)

	if wait_err == nil && state.exit_code != c.expect.exit_code {
		append(&problems, fmt.tprintf("exit code %d, expected %d", state.exit_code, c.expect.exit_code))
	}
	for s in c.expect.contains {
		if !strings.contains(output, s) {
			append(&problems, fmt.tprintf("missing output %q", s))
		}
	}
	for s in c.expect.excludes {
		if strings.contains(output, s) {
			append(&problems, fmt.tprintf("unexpected output %q", s))
		}
	}
	if strings.contains(output, "quit: ") && strings.count(output, "quit: ") != 1 {
		append(&problems, "app_quit ran more than once")
	}
	if !release {
		for count in c.expect.counts {
			if n := strings.count(output, count.text); n != count.n {
				append(&problems, fmt.tprintf("%q appeared %d times, expected %d", count.text, n, count.n))
			}
		}
		if strings.contains(output, "leaked ") || strings.contains(output, "bad free") {
			append(&problems, "Odin allocation leak reported")
		}
	}
	if len(problems) > 0 {
		append(&problems, fmt.tprintf("log: %s", log_path))
	}
	return problems[:]
}
