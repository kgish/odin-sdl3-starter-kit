// Lifecycle integration runner.
//
// Launches the real starter executable (startup adapter, SDL callbacks and
// all) once per case with SDL's dummy drivers, so SDL's main-thread
// requirements are met by the child process rather than a test worker thread.
//
// Usage: integration <exe> <log-dir> [--release] [--suite=starter|images|text]
//   --release  the executable logs at Info level, so skip checks that rely on
//              its Debug resource-destruction lines.
//   --suite    which executable's cases to run (default: starter).
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

// What app_quit destroyed, by the last init stage that created something.
DESTROYED_ALL :: []Count{{"destroyed background", 1}, {"destroyed ui atlas", 1}, {"destroyed audio stream", 1}, {"destroyed renderer", 1}, {"destroyed window", 1}}
DESTROYED_TO_AUDIO :: []Count{{"destroyed background", 0}, {"destroyed ui atlas", 0}, {"destroyed audio stream", 1}, {"destroyed renderer", 1}, {"destroyed window", 1}}
DESTROYED_BOTH :: []Count{{"destroyed background", 0}, {"destroyed ui atlas", 0}, {"destroyed audio stream", 0}, {"destroyed renderer", 1}, {"destroyed window", 1}}
DESTROYED_WINDOW :: []Count{{"destroyed background", 0}, {"destroyed ui atlas", 0}, {"destroyed audio stream", 0}, {"destroyed renderer", 0}, {"destroyed window", 1}}
DESTROYED_NONE :: []Count{{"destroyed background", 0}, {"destroyed ui atlas", 0}, {"destroyed audio stream", 0}, {"destroyed renderer", 0}, {"destroyed window", 0}}
DESTROYED_NO_BACKGROUND :: []Count{{"destroyed background", 0}, {"destroyed ui atlas", 1}, {"destroyed audio stream", 1}, {"destroyed renderer", 1}, {"destroyed window", 1}}
DESTROYED_MUTED :: []Count{{"destroyed background", 1}, {"destroyed ui atlas", 1}, {"destroyed audio stream", 0}, {"destroyed renderer", 1}, {"destroyed window", 1}}

STARTER_CASES := []Case{
	{
		"smoke", {"--frames=60"},
		{0, {"initialized", "loaded background 512x288", "audio driver: dummy", "smoke run complete after 60 frames", "quit: SUCCESS"}, nil, DESTROYED_ALL},
	},
	{
		"smoke-no-vsync", {"--frames=30", "--no-vsync"},
		{0, {"Hz callback rate", "quit: SUCCESS"}, nil, DESTROYED_ALL},
	},
	{
		"smoke-mute", {"--frames=10", "--mute"},
		{0, {"audio disabled (--mute)", "quit: SUCCESS"}, {"audio driver"}, DESTROYED_MUTED},
	},
	{
		"smoke-tuning", {"--frames=30", "--tuning", "--screenshot=tuning.bmp"},
		{0, {"tuning panel shown", "saved screenshot tuning.bmp", "smoke run complete after 30 frames", "quit: SUCCESS"}, nil, DESTROYED_ALL},
	},
	{
		"quit-event", {"--push-quit-at=3", "--frames=600"},
		{0, {"quit requested", "quit: SUCCESS"}, {"smoke run complete"}, DESTROYED_ALL},
	},
	{
		"missing-assets", {"--frames=5", "--assets=__missing_asset_dir__"},
		{0, {"asset directory not found: __missing_asset_dir__", "background not loaded", "smoke run complete", "quit: SUCCESS"}, nil, DESTROYED_NO_BACKGROUND},
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
		"fail-after-audio", {"--fail-after=audio"},
		{1, {"injected failure after stage Audio", "quit: FAILURE"}, nil, DESTROYED_TO_AUDIO},
	},
	{
		"fail-after-ui", {"--fail-after=ui"},
		{1, {"injected failure after stage Ui", "quit: FAILURE"}, nil, DESTROYED_NO_BACKGROUND},
	},
	{
		"fail-after-game", {"--fail-after=game"},
		{1, {"injected failure after stage Game", "quit: FAILURE"}, {"initialized"}, DESTROYED_ALL},
	},
}

IMAGES_CASES := []Case{
	{
		"smoke", {"--frames=30"},
		{0, {"loaded image 16x16", "smoke run complete after 30 frames", "quit: SUCCESS"}, nil,
		 {{"destroyed texture", 1}, {"destroyed renderer", 1}, {"destroyed window", 1}}},
	},
	{
		"screenshot", {"--frames=5", "--screenshot=images.bmp"},
		{0, {"saved screenshot images.bmp", "quit: SUCCESS"}, nil, nil},
	},
	{
		"missing-assets", {"--frames=5", "--assets=__missing_asset_dir__"},
		{1, {"failed to load image", "quit: FAILURE"}, {"smoke run complete"},
		 {{"destroyed texture", 0}, {"destroyed renderer", 1}, {"destroyed window", 1}}},
	},
	{
		"bad-option", {"--definitely-not-an-option"},
		{1, {"unknown option", "quit: FAILURE"}, nil, {{"destroyed window", 0}}},
	},
}

TEXT_CASES := []Case{
	{
		"smoke", {"--frames=30"},
		{0, {"FreeType", "loaded font", "smoke run complete after 30 frames", "quit: SUCCESS"}, nil,
		 {{"destroyed text engine", 1}, {"closed font", 1}, {"destroyed renderer", 1}, {"destroyed window", 1}}},
	},
	{
		"screenshot", {"--frames=5", "--screenshot=text.bmp"},
		{0, {"saved screenshot text.bmp", "quit: SUCCESS"}, nil, nil},
	},
	{
		"missing-assets", {"--frames=5", "--assets=__missing_asset_dir__"},
		{1, {"failed to load font", "quit: FAILURE"}, {"smoke run complete"},
		 {{"destroyed text engine", 0}, {"closed font", 0}, {"destroyed renderer", 1}, {"destroyed window", 1}}},
	},
	{
		"bad-option", {"--definitely-not-an-option"},
		{1, {"unknown option", "quit: FAILURE"}, nil, {{"destroyed window", 0}}},
	},
}

main :: proc() {
	if len(os.args) < 3 {
		fmt.eprintln("usage: integration <exe> <log-dir> [--release] [--suite=starter|images|text]")
		os.exit(2)
	}
	exe := os.args[1]
	log_dir := os.args[2]
	release := false
	cases := STARTER_CASES
	for arg in os.args[3:] {
		switch arg {
		case "--release":       release = true
		case "--suite=starter": cases = STARTER_CASES
		case "--suite=images":  cases = IMAGES_CASES
		case "--suite=text":    cases = TEXT_CASES
		case:
			fmt.eprintfln("unknown option %q", arg)
			os.exit(2)
		}
	}

	if err := os.make_directory_all(log_dir); err != nil && !os.is_dir(log_dir) {
		fmt.eprintfln("cannot create %s: %v", log_dir, err)
		os.exit(2)
	}

	env := headless_env()
	failed := 0
	for c in cases {
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

	fmt.printfln("%d/%d cases passed", len(cases) - failed, len(cases))
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
	// Inheritable: on Windows the child can only write to inherited handles.
	out, create_err := os.open(log_path, {.Write, .Create, .Trunc, .Inheritable}, os.Permissions_Default_File)
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
