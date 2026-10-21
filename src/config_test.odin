package main

import "core:path/filepath"
import "core:testing"

@(test)
defaults_are_valid :: proc(t: ^testing.T) {
	testing.expect_value(t, config_validate(config_default()), Config_Error.None)
}

@(test)
parses_options :: proc(t: ^testing.T) {
	cfg, err, _ := config_parse({"--frames=10", "--seed=99", "--no-vsync", "--mute", "--fail-after=audio", "--assets=/data"})
	testing.expect_value(t, err, Config_Error.None)
	testing.expect_value(t, cfg.smoke_frames, 10)
	testing.expect_value(t, cfg.seed, 99)
	testing.expect_value(t, cfg.vsync, false)
	testing.expect_value(t, cfg.sound, false)
	testing.expect_value(t, cfg.fail_after, Init_Stage.Audio)
	testing.expect_value(t, cfg.asset_dir, "/data")
}

@(test)
rejects_bad_options :: proc(t: ^testing.T) {
	_, err, bad := config_parse({"--frames=10", "--nope"})
	testing.expect_value(t, err, Config_Error.Unknown_Option)
	testing.expect_value(t, bad, "--nope")

	_, err, bad = config_parse({"--frames=ten"})
	testing.expect_value(t, err, Config_Error.Bad_Value)

	_, err, bad = config_parse({"--fail-after=everything"})
	testing.expect_value(t, err, Config_Error.Bad_Value)

	_, err, _ = config_parse({"--frames=-1"})
	testing.expect_value(t, err, Config_Error.Out_Of_Range)

	_, err, _ = config_parse({"--sim-hz=0"})
	testing.expect_value(t, err, Config_Error.Out_Of_Range)
}

@(test)
asset_dir_is_relative_to_executable :: proc(t: ^testing.T) {
	base := filepath.join({"opt", "starter"}, context.temp_allocator) or_else ""
	dir := resolve_asset_dir(base, "", context.temp_allocator)
	want := filepath.join({"opt", "starter", "assets"}, context.temp_allocator) or_else ""
	testing.expect_value(t, dir, want)
}

@(test)
asset_dir_override_wins :: proc(t: ^testing.T) {
	dir := resolve_asset_dir("/opt/starter", "/tmp/dev-assets", context.temp_allocator)
	testing.expect_value(t, dir, "/tmp/dev-assets")
}
