# Assets

The app resolves this directory relative to the executable (`<exe dir>/assets`),
never the working directory. `scripts/build.*` and `scripts/package.*` copy it
next to the built executable. Override during development with
`--assets=<dir>`.

The baseline example draws only rectangles and SDL's built-in debug text, so
there are no asset files yet.

## Provenance and licenses

Record every file you add here: source URL, author, license, and any
modifications. Ship the license texts with the packaged game.

| File | Source | Author | License |
| --- | --- | --- | --- |
