# Prompt for a separate session in `~/repos/rusty-backup`

Copy the section below into a fresh Claude Code session started in
`~/repos/rusty-backup`. It is self-contained — the agent will have no
context from the lbmactwo session that wrote it.

---

## Task: extend rusty-backup with HFS CLI subcommands

You are working in `~/repos/rusty-backup`. Before writing any code:

1. **Read `CONTRIBUTING.md` and `CLAUDE.md`** in this repo and follow the
   project's conventions (formatting, testing, commit style, etc.).
2. Read `src/lib.rs` and `src/main.rs` to see the current crate layout.
3. Skim `src/fs/hfs.rs` to confirm the library primitives listed below
   still exist with the same names.

### Why this work is needed

A separate project (a Macintosh II FPGA core called `lbmactwo_MiSTer`)
needs to build bootable Mac HFS disk images programmatically as part of
its test pipeline. The image will:

- Boot a Mac II (real silicon, the `Snow` emulator, our FPGA core, and
  our verilator sim of the core).
- Run a CPU test bench in supervisor mode from boot blocks.
- Write JSONL results back into a pre-allocated file on the same volume.
- Be retrieved on the host so the results can be diffed against an oracle.

rusty-backup already has full HFS read/write support inside its library
crate. What's missing is a *command-line* surface so a build script can
drive it. The user wants this exposed as a **subcommand of the existing
`rusty-backup` binary** (not a new binary, not a workspace split). If
no subcommand is on the argv, the GUI launches as today.

### Required subcommand surface

Add a top-level `hfs` subcommand with the following verbs. Image paths
are raw `.dsk` files (e.g. an 800K floppy is 819,200 bytes; a SCSI HD
image is any larger size). Mac paths use `:` or `/` separators — pick
one and document it.

| Verb | Args | Behavior |
|---|---|---|
| `rusty-backup hfs new <image> --size <bytes-or-KiB-or-MiB> --name <VolName>` | Create a fresh blank HFS volume of the given size. Default to 800K and `MacIIBench` if flags omitted. | Backed by `fs::hfs::create_blank_hfs_sized()` — verify the exact signature when you start. Support both floppy (800K) and arbitrary SCSI sizes (e.g. 5 MiB, 20 MiB). |
| `rusty-backup hfs info <image>` | — | Print volume name, total/free allocation blocks, file count, folder count, modify date. Backed by `HfsFilesystem::volume_summary()` (exists). |
| `rusty-backup hfs ls <image> [path]` | Optional path defaults to root. | Print entries (name, type, size). Backed by `list_children()`. |
| `rusty-backup hfs put <image> <host-file> <mac-path>` | `--type <FOUR>` (default `BINA`), `--creator <FOUR>` (default `????`), `--zero-pad <bytes>` (optional: instead of using host-file content, write that many zero bytes — for pre-allocating Results.jsonl). | Copy host file into HFS at the given Mac path. Create the file if absent; fail (or overwrite with `--force`) if present. Backed by `EditableFilesystem::create_file()`. |
| `rusty-backup hfs get <image> <mac-path> <host-file>` | — | Extract HFS file to host. |
| `rusty-backup hfs rm <image> <mac-path>` | — | Delete a file from the HFS catalog. |
| `rusty-backup hfs put-boot <image> <bb-file>` | — | Raw write of up to 1024 bytes at image offset 0 (HFS boot blocks live in sectors 0–1, outside the catalog). This is a direct `File::seek(0); write(...)` — do *not* route through the HFS B-tree; it would be wrong. Refuse if the source file is larger than 1024 bytes. |

Choose `clap` (derive API) for argument parsing if not already a
dependency — it's the de-facto standard. Check `Cargo.toml` first; if
something else is already in use, follow that.

### How CLI dispatch should integrate with the existing main.rs

`src/main.rs` currently always launches the egui app. Add at the top of
`main()`:

1. Parse argv with clap. If no subcommand was given, fall through to the
   existing GUI launch (preserve current behavior verbatim).
2. If a subcommand was given, run the CLI flow and `process::exit()`
   with appropriate status — do not call `eframe::run_native`.
3. Do not regress the panic hook, env-logger, or Linux elevation logic
   for the GUI path. The CLI path should not need elevation for `.dsk`
   file work, so it's fine to skip the elevation block in CLI mode.

### Implementation notes / gotchas

- `create_blank_hfs_sized` writes an empty volume. You may also need to
  pre-allocate the underlying `.dsk` file to the requested size first
  (`File::set_len`). Verify whether the library does this for you.
- HFS file names are Mac Roman, 1–31 chars, no `:`. The library has
  `utf8_to_mac_roman` + `validate_hfs_create_name`. Surface useful
  errors when the user passes an invalid name.
- `put-boot` must write *exactly* the supplied bytes at offset 0 and
  must not zero-pad past the source length — the rest of sectors 0/1
  may contain MDB-adjacent metadata that the HFS library wrote during
  `new`. (Actually the MDB lives at sector 2, not sector 0/1 — but
  still, only overwrite what the user provided.)
- After `put` / `rm` / `put-boot`, the image file should be left in a
  state that mounts cleanly on a real Mac. If the library exposes a
  fsck/validate entry point, run it (or expose a `validate` verb)
  before returning success. There's a `validate_hfs_integrity()`
  function in `src/fs/hfs.rs` — wire it up.

### Tests to add

Follow the test conventions in `tests/` (read existing test files
first). At minimum:

- Round-trip: `new` → `put` host file → `get` it back → bytes match.
- `put-boot` writes exactly N bytes and leaves the HFS catalog intact
  (mount + `ls` still succeeds afterward).
- `new --size 800K` produces a 819,200-byte file that another tool
  (the library's own reader) parses without errors.
- A larger size (e.g. 5 MiB) for the SCSI use case.

### Out of scope (do not do)

- No GUI changes.
- No HFS+ work; classic HFS only.
- No Mac II / 68k / boot-block content concerns — that's done in the
  other repo. This task is just the host-side image-construction CLI.
- No new bin target; this is a subcommand of `rusty-backup`.

### Done definition

- `cargo build --release` succeeds.
- `cargo test` is green.
- `rusty-backup hfs --help` lists every verb above.
- A one-line example for each verb works against a freshly-created
  800K image.
- CONTRIBUTING.md's commit/PR conventions followed; changes committed
  with a clear message.

---

When this work is done, control returns to the lbmactwo_MiSTer session
to write the 68k boot stub and bench code that consumes this CLI.
