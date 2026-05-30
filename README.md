# LeoUI

A tiny, dependency-free TUI library for Bash 4+. Single-file
(`leoui.sh`), drop-in: copy it next to your script, `source` it,
and you get a complete set of primitives for building boxed,
menu-driven shell programs.

> Spanish version: [README.es.md](./README.es.md)

## Features

- **Box drawing primitives** (`╔═╗ ║ ╚═╝`) with a configurable
  width (default 52 columns).
- A **spinner-backed command runner** that propagates the real
  exit code of the wrapped command and shows `Okay [✔]` /
  `Error [✖]` accordingly.
- **Declarative menus** with nesting, `@back` and `@exit`
  sentinels, and graceful failure handling.
- **Prompts, confirmations, pause, and numbered selects** with
  default values, whitespace trimming and a single visual model
  (every interaction stays inside the box).
- **Auto-open boxes**: any drawing call works even if you forgot
  `ui_box_top`.
- **Auto-detected colors** (green / red / dim) with an opt-out.
- **Signal-safe**: `EXIT` / `INT` / `TERM` traps close the box
  cleanly and reap the spinner background process so Ctrl+C
  never leaves a broken terminal behind.
- **Non-TTY mode**: every interactive helper falls back to safe
  defaults so the same script works in CI / pipes / cron.

## Requirements

- Bash 4.0 or newer (uses `local -n` namerefs and `${var,,}`
  case folding).
- A UTF-8 terminal is recommended (the library prints
  `║ ═ ╔ ╗ ╚ ╝ ✔ ✖`).
- `tput` is optional. When present and the terminal supports
  ≥ 8 colors, output is colored automatically.

## Installation

Copy `leoui.sh` into your project and source it:

```bash
source ./leoui.sh
ui_init "your-name"          # signature in the box footer
```

Sourcing the file is **idempotent** — guarded by `LEOUI_LOADED`,
so you can `source` it from multiple files without
double-installation of traps or state.

## Visual model

A *box* is opened with `ui_box_top` and stays open until
`ui_box_bottom`. While a box is open:

- Only **one box** is visible on screen — `ui_box_top` always
  clears the screen first.
- The **footer** with the author signature is permanently
  rendered at the bottom and re-drawn after every operation.
- Every other function (`ui_box_line`, `ui_run`, `ui_prompt`,
  `ui_confirm`, `ui_pause`, `ui_select`, …) inserts its output
  as a new row inside the box, pushing the footer one line down.
- If a drawing helper is called **without** an open box, a
  default box (titled `Output`) is auto-opened so you never get
  orphan rows.

This guarantees prompts, spinners and confirmations all happen
*inside* the box, never below it.

## Quick example

```bash
#!/usr/bin/env bash
source ./leoui.sh
ui_init "alice"

greet() {
    ui_box_top "Greeting"
    ui_box_line "Hello, world!"
    ui_box_paragraph "ui_box_paragraph wraps long sentences over \
several rows so prose text fits inside the box without manual \
splitting."
    ui_pause
    ui_box_bottom
}

install_things() {
    ui_box_top "Install"
    ui_run "Updating apt"      sudo apt update
    ui_run "Installing curl"   sudo apt install -y curl
    ui_pause
    ui_box_bottom
}

confirm_dangerous() {
    ui_box_top "Confirm"
    ui_box_line "About to perform a dangerous action."
    if ui_confirm "Proceed?" no; then    # default = no
        ui_box_line "User said YES."
    else
        ui_box_line "User said NO."
    fi

    local theme
    ui_select theme "Pick a theme" "Dark" "Light" "Auto"
    ui_box_line "Selected theme: ${theme}"

    ui_pause
    ui_box_bottom
}

menu_main() {
    local entries=(
        "Say hello|greet"
        "Install things|install_things"
        "Confirm something|confirm_dangerous"
        "---"
        "Exit|@exit"
    )
    ui_menu "LeoUI Demo" entries
}

menu_main
```

Run `examples/00_master.sh` for a fully-commented tour of every
public function.

## Configuration

`ui_init` is the only configuration entry point. Everything else
is read from public variables (see the
[Variables](#variables-you-can-set) section).

```bash
ui_init                    # author=LeoUI,  width=52
ui_init "alice"            # author=alice,  width=52
ui_init "alice" 64         # author=alice,  width=64
```

To force-disable colors, set `UI_COLOR=0` **before** sourcing the
library:

```bash
UI_COLOR=0 source ./leoui.sh
```

## API reference

Legend:

- `<arg>`   — required positional argument
- `[arg]`   — optional positional argument
- `<arg>…`  — required, takes one or more values

### Initialization

#### `ui_init [author] [width]`

Configure the library. Both parameters are optional.

| Parameter | Default  | Description                                         |
| --------- | -------- | --------------------------------------------------- |
| `author`  | `LeoUI`  | Signature shown on the right side of every footer.  |
| `width`   | `52`     | Total box width in columns. Clamped to a minimum of 30. |

`width` recomputes all derived widths
(`UI_INNER_WIDTH = width-2`, `UI_TEXT_WIDTH = width-4`,
`UI_TITLE_WIDTH = width-22`).

```bash
ui_init "alice" 60
```

### Box lifecycle

#### `ui_box_top <title>`

Clear the screen and open a new box. The title is centered, with
10 `═` characters on each side, and truncated to fit
`UI_TITLE_WIDTH` columns. Sets `UI_BOX_OPEN=1`.

#### `ui_box_bottom`

Close the currently open box (emits a trailing newline). No-op
if no box is open. Sets `UI_BOX_OPEN=0`.

#### `ui_clear`

Run the system `clear` command and reset `UI_BOX_OPEN=0`. Rarely
needed because `ui_box_top` already clears.

### Content rows

All four functions auto-open a default box (titled `Output`) if
no box is currently open.

#### `ui_box_line <text>`

Append a content row. `<text>` is hard-truncated to
`UI_TEXT_WIDTH` visible columns (no ellipsis).

#### `ui_box_paragraph <text>`

Append `<text>` as one or more rows, performing simple
whitespace-based word wrap so each row fits within
`UI_TEXT_WIDTH`. Words longer than the line width are emitted
on their own row and may overflow visually (degenerate case).

```bash
ui_box_paragraph "Lorem ipsum dolor sit amet, consectetur \
adipiscing elit, sed do eiusmod tempor incididunt."
```

#### `ui_box_blank`

Append a single empty row.

#### `ui_box_separator`

Append a horizontal divider rendered as `╠═══╣` across the full
inner width.

### Command execution

#### `ui_run <msg> <cmd> [args…]`

Run `cmd args…` in the background while animating a spinner on a
content row labeled `<msg>`. When the command finishes the row is
replaced with:

- `Okay  [✔]` (green) on `rc == 0`
- `Error [✖]` (red)   on `rc != 0`

The function **returns the real exit code** of the command, so
you can branch on it:

```bash
if ui_run "Building" make -j4; then
    ui_box_line "Build succeeded."
else
    ui_box_line "Build failed."
fi
```

| Behavior        | Detail |
| --------------- | ------ |
| Stdout / stderr | Silenced (redirected to `/dev/null`). |
| Background pid  | Tracked in `_UI_RUN_PID` so the EXIT/INT trap can reap it. |
| `set -e`        | Compatible — failures must be guarded with `\|\|` if you don't want them to abort. |
| Auto-open       | Yes — opens a default box if none is open. |
| Spinner frames  | `\| / - \\` rotated every `0.1` s. |

### Notifications

#### `ui_notify <msg>`

Append an error row formatted as `<msg> ... Error [✖]` (red). A
blank row is inserted before the notification for visual
breathing space. Auto-opens a box if none is open. **Does not
exit.**

#### `ui_error <msg>`

Same as `ui_notify`, then closes the open box (if any) and calls
`exit 1`.

### Interactive input

All interactive functions render **inside** the open box (the
right border and footer remain visible while the user types) and
fall back to safe defaults when stdin/stdout is not a TTY (CI
logs, pipes, cron, etc.).

#### `ui_prompt <question> <var_name> [default]`

Free-form text input. Stores the answer in the variable named by
`<var_name>` (no `$`).

| Parameter   | Description |
| ----------- | ----------- |
| `question`  | Plain question text. The library appends `:` (or `[default]:` if a default is given). |
| `var_name`  | Name of the variable to write to. |
| `default`   | Optional default; pressing Enter selects it. |

Non-TTY behavior: silently writes `default` (or empty string) to
the variable without prompting.

```bash
local name
ui_prompt "What is your name?" name "anonymous"
```

#### `ui_confirm <question> [default]`

Yes / no prompt. Accepts `y / yes / s / si / sí` and `n / no`,
case-insensitive, with surrounding whitespace trimmed. Returns
`0` for yes, `1` for no. Re-prompts on invalid input.

| `default`        | Suffix shown | Enter selects |
| ---------------- | ------------ | ------------- |
| _omitted_ / `""` | `(y/n):`     | _none, loops_ |
| `yes` / `y`      | `(Y/n):`     | yes           |
| `no`  / `n`      | `(y/N):`     | no            |

Non-TTY behavior: returns the default (`no` if no default).

```bash
if ui_confirm "Delete temporary files?" no; then
    rm -rf /tmp/foo
fi
```

#### `ui_pause [msg]`

Wait for the user to press Enter. The prompt row is erased after
Enter so the box stays clean.

| Parameter | Default                     |
| --------- | --------------------------- |
| `msg`     | `Press Enter to continue`   |

Non-TTY behavior: no-op (returns immediately).

#### `ui_select <var_name> <prompt> <option1> [option2 …]`

Numbered single-choice picker. Lists the options as a numbered
menu, reads a number from the user, and stores the **chosen
string** (not the index) into the variable named by `<var_name>`.

- If a box is open, `<prompt>` is added as a content row above
  the option list.
- If no box is open, a new box titled `<prompt>` is opened and
  closed automatically around the picker.

Non-TTY behavior: writes the **first option** to the variable
without prompting.

```bash
local env
ui_select env "Pick environment" "dev" "staging" "production"
```

### Menus

#### `ui_menu <title> <array_var_name>`

Render an interactive menu and loop until a sentinel is selected.

The array passed by name contains one entry per row. Each entry
is a single string with one of the following forms:

| Entry              | Meaning                                                                |
| ------------------ | ---------------------------------------------------------------------- |
| `"Label\|action"`  | Calls `action` (function or command, whitespace-separated args). After it returns, the menu re-renders. |
| `"Label\|@back"`   | Returns from this menu to its caller.                                  |
| `"Label\|@exit"`   | Exits the program (`exit 0`).                                          |
| `"---"`            | Horizontal separator row.                                              |
| `""`               | Blank row.                                                             |

**Numbering.** Selectable entries are numbered `1..N` in the
order they appear. Any entry whose action is `@back` or `@exit`
is numbered `0` instead.

**Submenus** are simply functions that call `ui_menu` again. A
submenu typically ends with `"Back|@back"`.

**Error handling.** When an action exits with a non-zero status,
LeoUI shows an `Error [✖]` notification, waits for Enter, and
redraws the menu. The program does **not** abort.

**Non-TTY behavior.** Menus require a real terminal. In non-TTY
mode `ui_menu` emits `ui_notify "ui_menu '<title>' requires an
interactive terminal"` and returns `1`.

```bash
sub_menu_themes() {
    local entries=(
        "Dark|apply_dark"
        "Light|apply_light"
        "---"
        "Back|@back"
    )
    ui_menu "Themes" entries
}

main_menu() {
    local entries=(
        "Themes|sub_menu_themes"
        "Quit|@exit"
    )
    ui_menu "Main" entries
}
```

## Color support

Colors are auto-detected at source time:

- `stdout` must be a TTY.
- `tput colors` must report `≥ 8`.

When supported, the library renders:

- `Okay  [✔]` in green
- `Error [✖]` in red
- The author signature in dim

To force-disable colors, set `UI_COLOR=0` **before** sourcing
`leoui.sh`. The auto-detection respects this:

```bash
UI_COLOR=0 source ./leoui.sh
```

ANSI escape sequences have **zero visible width**, so column
alignment is preserved whether colors are on or off.

## Signal handling

When sourced into a **non-interactive** shell (i.e. a script —
the typical case), LeoUI installs the following traps:

| Signal | Action                                                       |
| ------ | ------------------------------------------------------------ |
| `EXIT` | Close any open box and reap the spinner background pid.      |
| `INT`  | Same, then `exit 130` (the conventional Ctrl+C exit code).   |
| `TERM` | Same, then `exit 143`.                                       |

This guarantees that hitting Ctrl+C during a spinner or a prompt
never leaves an orphan background process or a half-rendered
box.

When sourced into an **interactive** shell, the traps are **not**
installed (we don't want to override your shell session). If a
script needs different behavior, it can override the traps after
sourcing — bash's trap is last-write-wins.

## Non-TTY mode

The library detects a non-interactive environment via
`[[ -t 0 && -t 1 ]]`. When either stdin or stdout is not a TTY,
interactive helpers degrade gracefully so the same script can run
unattended in CI, cron, pipes, redirects, etc.:

| Function       | Non-TTY behavior                                |
| -------------- | ----------------------------------------------- |
| `ui_pause`     | No-op, returns immediately.                     |
| `ui_prompt`    | Stores the default (or `""`) without prompting. |
| `ui_confirm`   | Returns the default (`no` if not given).        |
| `ui_select`    | Picks the first option silently.                |
| `ui_menu`      | Emits an error notification, returns `1`.       |

Drawing helpers (`ui_box_top`, `ui_box_line`, `ui_run`, …) still
run normally — the resulting output looks like a "boxed log" in
the captured stream.

## Variables you can set

Set these **before** sourcing `leoui.sh` to influence its
behavior. After sourcing, they are populated/overwritten by
`ui_init`.

| Variable             | Default      | Purpose                                                        |
| -------------------- | ------------ | -------------------------------------------------------------- |
| `UI_COLOR`           | _auto_       | `0` to force-disable colors, otherwise auto-detected.          |
| `UI_AUTHOR`          | `LeoUI`      | Signature shown in the footer (also set by `ui_init`).         |
| `UI_BOX_TOTAL`       | `52`         | Total box width in columns (also set by `ui_init`).            |
| `UI_AUTO_BOX_TITLE`  | `Output`     | Title used when a draw helper auto-opens a box.                |

You can also read these for inspection:

| Variable        | Meaning                                                   |
| --------------- | --------------------------------------------------------- |
| `UI_BOX_OPEN`   | `1` while a box is open, `0` otherwise.                   |
| `UI_INNER_WIDTH`| `UI_BOX_TOTAL - 2` (between the side borders).            |
| `UI_TEXT_WIDTH` | `UI_BOX_TOTAL - 4` (usable text column count).            |
| `UI_TITLE_WIDTH`| Maximum visible title width inside `ui_box_top`.          |
| `_UI_RUN_PID`   | Background pid of the currently-running `ui_run` job.     |

## Notes and limitations

- Distances are computed using **spaces only** — no tab
  characters appear in the output, so rendering is independent
  of the user's tabstop setting.
- The library uses a single fixed width set at `ui_init`. If you
  need different box widths in the same script, call `ui_init`
  again with a new width before opening the next box.
- Action strings in menus are split on whitespace and invoked
  **without `eval`**. To pass arguments containing spaces, wrap
  the call in a function and reference that function in the
  menu entry.
- Use a UTF-8 locale. Under `LC_ALL=C` user-supplied labels
  containing multi-byte characters will be miscounted by
  `${#var}` (the library only handles its own internal `✔`/`✖`
  glyphs correctly in any locale).
- Wide / CJK / emoji characters in user content are counted as
  one column even though they take two visible columns; box
  alignment will be off in that case.
- `_ui_read_overlay` uses the DEC `\033[s` / `\033[u` save /
  restore cursor sequences, supported by every modern terminal
  (xterm, gnome-terminal, kitty, alacritty, foot, wezterm, …)
  but missing on some pure VT100s.

## License

MIT
