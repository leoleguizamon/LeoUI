#!/usr/bin/env bash
# =================================================================
#  LeoUI - a minimal TUI library for Bash 4+
# =================================================================
#  Source this file from your script:
#      source ./leoui.sh
#      ui_init "your-name"
#
#  Public API:
#
#    Setup
#      ui_init [author] [width]   - configure signature + box width (default 52)
#
#    Box lifecycle
#      ui_box_top <title>         - open a box (auto-clears screen)
#      ui_box_bottom              - close the box
#      ui_clear                   - clear the screen + reset state
#
#    Content rows (auto-open a default box if none is open)
#      ui_box_line <text>         - append a content row (truncated)
#      ui_box_paragraph <text>    - append word-wrapped paragraph
#      ui_box_blank               - append an empty row
#      ui_box_separator           - append a divider row (╠═══╣)
#
#    Execution & notifications
#      ui_run <msg> <cmd>...      - spinner + colored Okay/Error
#      ui_notify <msg>            - error row (red), no exit
#      ui_error  <msg>            - error row, then exit 1
#
#    Interaction (fall back to defaults in non-TTY mode)
#      ui_prompt  <q> <var> [d]   - free-form text input
#      ui_confirm <q> [d]         - y/n (d = "yes"/"no" for default)
#      ui_pause   [msg]           - press-Enter to continue
#      ui_select  <var> <prompt> <opt1> [...]   - numbered picker
#      ui_menu    <title> <array_var>           - persistent menu
#
#  Menu entries (array passed to ui_menu):
#      "Label|action"   - call action (function with args)
#      "Label|@back"    - return to parent menu
#      "Label|@exit"    - exit the program (exit 0)
#      "---"            - divider row
#      ""               - blank row
#
#  Visual model: a "box" is opened by ui_box_top, which prints a
#  header and leaves the footer permanently visible at the bottom.
#  Every other content function (rows, spinner, prompts) overlays
#  the footer with new content and re-renders the footer below.
#  This guarantees that only one box is visible at a time, the
#  footer signature is always shown, and prompts render inside.
#
#  Colors: auto-detected via tput; set UI_COLOR=0 to disable.
#  Signal handling: EXIT / INT / TERM traps close any open box and
#    reap the spinner pid, so Ctrl+C never leaves the terminal in
#    a broken state. (Traps install only when sourced into a
#    non-interactive shell - i.e. inside scripts.)
#  Non-TTY mode: prompts/menus auto-degrade so the same script can
#    run in CI / pipes without hanging.
#
#  Requires: bash >= 4.0, UTF-8 terminal recommended.
#  License:  MIT
# =================================================================

[[ -n "${LEOUI_LOADED:-}" ]] && return 0
LEOUI_LOADED=1

if (( BASH_VERSINFO[0] < 4 )); then
    echo "LeoUI requires Bash 4.0 or newer (current: $BASH_VERSION)" >&2
    return 1 2>/dev/null || exit 1
fi

# -----------------------------------------------------------------
# Layout (configurable through ui_init, defaults shown below)
# -----------------------------------------------------------------
#     ╔══════════ ... ══════════╗   <- UI_BOX_TOTAL columns
#     ║<........INNER..........>║   <- UI_INNER_WIDTH chars
#     ║ <........TEXT.........> ║   <- UI_TEXT_WIDTH usable text
#     ╚══════════ ... ══════════╝
UI_BOX_TOTAL=52
UI_INNER_WIDTH=50
UI_TEXT_WIDTH=48
UI_TITLE_WIDTH=30

readonly UI_SPIN_FRAMES='|/-\'
readonly UI_SPIN_DELAY=0.1

# Both suffixes have the same VISUAL width (9 columns). Using a
# constant because `${#}` counts bytes under LC_ALL=C and ✔/✖ are
# 3-byte UTF-8 sequences that would skew alignment.
readonly UI_SUFFIX_OK='Okay  [✔]'
readonly UI_SUFFIX_ERR='Error [✖]'
readonly UI_SUFFIX_VISUAL_WIDTH=9

readonly UI_CURSOR_UP=$'\033[F'
readonly UI_CLEAR_LINE=$'\033[2K'

# -----------------------------------------------------------------
# Color support (auto-detected at source time, can be forced via
# UI_COLOR=0 in the caller's environment before sourcing).
# -----------------------------------------------------------------
UI_C_RESET=''
UI_C_OK=''
UI_C_ERR=''
UI_C_DIM=''

_ui_detect_colors() {
    # Honor an explicit UI_COLOR=0 override.
    [[ ${UI_COLOR:-auto} == 0 ]] && { UI_COLOR=0; return; }
    # Require a TTY on stdout AND a 8+ color terminal.
    if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
        local n
        n=$(tput colors 2>/dev/null || echo 0)
        if (( n >= 8 )); then
            UI_COLOR=1
            UI_C_RESET=$'\033[0m'
            UI_C_OK=$'\033[32m'       # green
            UI_C_ERR=$'\033[31m'      # red
            UI_C_DIM=$'\033[2m'       # dim / faint
            return
        fi
    fi
    UI_COLOR=0
}
_ui_detect_colors

# -----------------------------------------------------------------
# Runtime state
# -----------------------------------------------------------------
UI_AUTHOR='LeoUI'
UI_BOX_OPEN=0                # 1 while a box is open (footer visible)
UI_AUTO_BOX_TITLE='Output'   # title used when a draw function
                             # auto-opens a box because none was open
_UI_RUN_PID=''               # pid of the spinner's background job
                             # (so the EXIT/INT trap can reap it)


# =================================================================
# Initialization
# =================================================================

# ui_init [author] [width]
#   Configure the library.
#     author : signature embedded in the footer (default "LeoUI")
#     width  : total box width in columns (default 52). Clamped to
#              a sane minimum of 30 columns.
#   All derived widths (inner / text / title) are recomputed.
ui_init() {
    UI_AUTHOR=${1:-LeoUI}

    local width=${2:-52}
    (( width < 30 )) && width=30
    UI_BOX_TOTAL=$width
    UI_INNER_WIDTH=$(( width - 2 ))
    UI_TEXT_WIDTH=$(( width - 4 ))
    # Title sits between two 10-char ═ runs (20 cols of border).
    UI_TITLE_WIDTH=$(( UI_INNER_WIDTH - 20 ))
    (( UI_TITLE_WIDTH < 5 )) && UI_TITLE_WIDTH=5
}


# =================================================================
# Internal helpers (prefix _ui_, not public API)
# =================================================================

# _ui_repeat <char> <count>
_ui_repeat() {
    local char=$1
    local n=$2
    local pad
    (( n <= 0 )) && return
    printf -v pad '%*s' "$n" ''
    printf '%s' "${pad// /$char}"
}

# _ui_footer
#   Print the footer line WITHOUT trailing newline. The overlay
#   machinery uses this to keep the footer permanently visible.
#   The author signature is rendered dim when colors are enabled.
_ui_footer() {
    local fill=$(( UI_INNER_WIDTH - ${#UI_AUTHOR} - 1 ))
    printf '╚'
    _ui_repeat '═' "$fill"
    printf '%s%s%s═╝' "$UI_C_DIM" "$UI_AUTHOR" "$UI_C_RESET"
}

# _ui_overlay_begin
#   Position the cursor at column 0 of the CURRENT line (where the
#   footer was just rendered, no trailing newline) and clear it,
#   so the caller can print new content over it. The caller is
#   expected to print "content\n" followed by _ui_footer, which
#   pushes the footer one line down and keeps it visible.
#   Pre-condition: UI_BOX_OPEN=1.
_ui_overlay_begin() {
    printf '\r%s' "$UI_CLEAR_LINE"
}

# _ui_is_tty
#   True (rc=0) when BOTH stdin and stdout are connected to a
#   terminal. Used by interactive helpers (ui_prompt, ui_confirm,
#   ui_pause, ui_menu, ui_select) to fall back to safe defaults
#   when running non-interactively (CI logs, pipes, redirects).
_ui_is_tty() {
    [[ -t 0 && -t 1 ]]
}

# _ui_ensure_box
#   Make sure a box is currently open. If none is, auto-open one
#   with the default title (UI_AUTO_BOX_TITLE). This lets the
#   drawing helpers be called from any script even if the caller
#   forgot to open a box explicitly, instead of producing an
#   orphan row + footer with no header.
_ui_ensure_box() {
    (( UI_BOX_OPEN )) || ui_box_top "$UI_AUTO_BOX_TITLE"
}

# _ui_cleanup
#   Invoked from EXIT / INT / TERM traps so the terminal is left
#   in a sane state when the script ends or the user hits Ctrl+C:
#     1. Kill the spinner background job (if any) and reap it.
#     2. Close the currently open box (if any).
#   Idempotent and safe to call multiple times.
_ui_cleanup() {
    if [[ -n ${_UI_RUN_PID:-} ]] && kill -0 "$_UI_RUN_PID" 2>/dev/null; then
        kill "$_UI_RUN_PID" 2>/dev/null
        wait "$_UI_RUN_PID" 2>/dev/null
        _UI_RUN_PID=''
    fi
    (( UI_BOX_OPEN )) && ui_box_bottom
}


# =================================================================
# Drawing primitives
# =================================================================

# ui_clear
#   Clear the terminal screen.
ui_clear() {
    clear
    UI_BOX_OPEN=0
}

# ui_box_top <title>
#   Open a box. Always clears the screen first so that only one
#   header is ever visible. Prints header + initial blank row +
#   footer (no trailing newline). Leaves UI_BOX_OPEN=1.
ui_box_top() {
    clear
    local title=${1:-}
    title=${title:0:UI_TITLE_WIDTH}
    local len=${#title}

    local pad_left=$(( (UI_TITLE_WIDTH - len) / 2 ))
    local pad_right=$(( UI_TITLE_WIDTH - len - pad_left ))
    (( pad_left  < 0 )) && pad_left=0
    (( pad_right < 0 )) && pad_right=0

    printf '╔'
    _ui_repeat '═' 10
    printf '%*s%s%*s' "$pad_left" '' "$title" "$pad_right" ''
    _ui_repeat '═' 10
    printf '╗\n'
    printf '║%*s║\n' "$UI_INNER_WIDTH" ''
    _ui_footer
    UI_BOX_OPEN=1
}

# ui_box_bottom
#   Close the currently open box. Just emits a newline so the
#   cursor moves below the footer (which is already drawn).
ui_box_bottom() {
    (( UI_BOX_OPEN )) || return 0
    printf '\n'
    UI_BOX_OPEN=0
}

# ui_box_line <text>
#   Append a content row above the footer. Auto-opens a default
#   box if no box is currently open.
ui_box_line() {
    _ui_ensure_box
    local text=${1:-}
    _ui_overlay_begin
    printf '║ %-*.*s ║\n' "$UI_TEXT_WIDTH" "$UI_TEXT_WIDTH" "$text"
    _ui_footer
}

# ui_box_blank
#   Append an empty row above the footer. Auto-opens a default
#   box if no box is currently open.
ui_box_blank() {
    _ui_ensure_box
    _ui_overlay_begin
    printf '║%*s║\n' "$UI_INNER_WIDTH" ''
    _ui_footer
}

# ui_box_separator
#   Append a horizontal divider (╠═══╣) above the footer.
#   Auto-opens a default box if no box is currently open.
ui_box_separator() {
    _ui_ensure_box
    _ui_overlay_begin
    printf '╠'
    _ui_repeat '═' "$UI_INNER_WIDTH"
    printf '╣\n'
    _ui_footer
}

# ui_box_paragraph <text>
#   Append <text> as one or more content rows, performing simple
#   word-wrap so each visual line fits within UI_TEXT_WIDTH.
#   Words longer than the line width are emitted on their own row
#   and may overflow visually (degenerate case).
ui_box_paragraph() {
    _ui_ensure_box
    local text=${1:-}
    local width=$UI_TEXT_WIDTH
    local line='' word

    # Unquoted $text exploits word splitting on IFS whitespace.
    for word in $text; do
        if [[ -z $line ]]; then
            line=$word
        elif (( ${#line} + 1 + ${#word} <= width )); then
            line="$line $word"
        else
            ui_box_line "$line"
            line=$word
        fi
    done
    [[ -n $line ]] && ui_box_line "$line"
}


# =================================================================
# Command execution with spinner feedback
# =================================================================

# ui_run <msg> <cmd> [args...]
#   Run <cmd> in the background while animating a spinner in a
#   content row above the footer. The footer stays visible during
#   the whole animation. When the command finishes, the row is
#   replaced with "Okay  [✔]" (green) or "Error [✖]" (red) and
#   the real exit code of the command is returned. stdout/stderr
#   are silenced. The background PID is exposed in _UI_RUN_PID so
#   the EXIT/INT trap can reap it if the user aborts.
#   Auto-opens a default box if no box is currently open.
ui_run() {
    _ui_ensure_box

    local msg=$1
    shift

    local msg_width=$(( UI_TEXT_WIDTH - 4 ))  # 4 cols for " [x]"

    # Insert the initial spinner row above the footer.
    _ui_overlay_begin
    printf '║ %-*.*s [%s] ║\n' \
        "$msg_width" "$msg_width" "$msg" "${UI_SPIN_FRAMES:0:1}"
    _ui_footer

    "$@" >/dev/null 2>&1 &
    _UI_RUN_PID=$!
    local pid=$_UI_RUN_PID
    local i=0
    local frame

    # Each iteration:
    #   - cursor is at the end of the footer line
    #   - \033[F moves up one line to the start of the spinner row
    #   - \033[2K clears the spinner row
    #   - print new frame + \n -> cursor lands at start of footer row
    #   - \033[2K clears the (stale) footer
    #   - reprint the footer; cursor ends at its right side
    while kill -0 "$pid" 2>/dev/null; do
        sleep "$UI_SPIN_DELAY"
        i=$(( i + 1 ))
        frame=${UI_SPIN_FRAMES:i%${#UI_SPIN_FRAMES}:1}
        printf '%s%s' "$UI_CURSOR_UP" "$UI_CLEAR_LINE"
        printf '║ %-*.*s [%s] ║\n' \
            "$msg_width" "$msg_width" "$msg" "$frame"
        printf '%s' "$UI_CLEAR_LINE"
        _ui_footer
    done

    wait "$pid" 2>/dev/null
    local rc=$?
    _UI_RUN_PID=''

    # Pick the colored suffix matching the exit status.
    local color suffix_text
    if (( rc == 0 )); then
        color=$UI_C_OK
        suffix_text=$UI_SUFFIX_OK
    else
        color=$UI_C_ERR
        suffix_text=$UI_SUFFIX_ERR
    fi
    local suffix="${color}${suffix_text}${UI_C_RESET}"
    local final_width=$(( UI_TEXT_WIDTH - UI_SUFFIX_VISUAL_WIDTH - 1 ))

    # Replace the spinner row with the final status, then re-render
    # the footer. Note: the color codes have zero visible width so
    # the column alignment is unaffected.
    printf '%s%s' "$UI_CURSOR_UP" "$UI_CLEAR_LINE"
    printf '║ %-*.*s %s ║\n' \
        "$final_width" "$final_width" "$msg" "$suffix"
    printf '%s' "$UI_CLEAR_LINE"
    _ui_footer

    return "$rc"
}


# =================================================================
# Notifications
# =================================================================

# _ui_error_row <msg>
#   Internal: render a row formatted as "msg ... Error [✖]".
#   The suffix is colored red when colors are enabled. The color
#   escape sequences have zero visible width so the alignment
#   remains correct.
_ui_error_row() {
    local msg=${1:-Error}
    local width=$(( UI_TEXT_WIDTH - UI_SUFFIX_VISUAL_WIDTH - 1 ))
    local suffix="${UI_C_ERR}${UI_SUFFIX_ERR}${UI_C_RESET}"
    printf '║ %-*.*s %s ║\n' "$width" "$width" "$msg" "$suffix"
}

# ui_notify <msg>
#   Show an error notification. Auto-opens a default box if no box
#   is currently open. A blank row is inserted before the
#   notification for visual breathing space.
ui_notify() {
    _ui_ensure_box
    local msg=${1:-Error}
    ui_box_blank
    _ui_overlay_begin
    _ui_error_row "$msg"
    _ui_footer
}

# ui_error <msg>
#   Show an error notification and exit 1. If a box is open it is
#   closed cleanly before exiting.
ui_error() {
    ui_notify "${1:-Error}"
    (( UI_BOX_OPEN )) && ui_box_bottom
    exit 1
}


# =================================================================
# Input helpers (rendered inside the open box)
# =================================================================

# _ui_read_overlay <prompt_text> <var_name>
#   Internal: render a complete prompt row INSIDE the open box and
#   read user input. The box stays fully closed during the read -
#   both the right "║" of the prompt row AND the bottom border
#   (footer) remain visible while the user types.
#
#   How it works:
#     1. The footer's row is cleared by _ui_overlay_begin.
#     2. The prompt is printed: "║  <text> " + filler + "║" + \n.
#     3. The footer is reprinted on the line BELOW the prompt.
#     4. The cursor is sent back (\033[u) to the position right
#        after the prompt label so `read` echoes the user's input
#        on top of the filler spaces.
#
#   <prompt_text> is the bare prompt (e.g. "Select option:")
#   WITHOUT the leading "║  " and WITHOUT a trailing space - this
#   function adds both.
#
#   Pre-condition:  UI_BOX_OPEN=1; cursor at end of footer line.
#   Post-condition: cursor at column 0 of the footer line (the
#   one BELOW the prompt). The footer is fully drawn there;
#   row R has the prompt+input. Callers should use either
#   _ui_finalize_row or _ui_restore_footer_at_prompt to clean up.
_ui_read_overlay() {
    local _leoui_text=$1
    local _leoui_var=$2
    # IMPORTANT: do NOT declare a local named like a likely caller
    # variable (e.g. `ans`). Bash uses dynamic scoping, so a local
    # here would shadow the caller's variable and `printf -v` below
    # would write into the (now-dying) local instead of the caller.
    # We use a uniquely-prefixed name to avoid that footgun.
    local _leoui_input

    # Visual breathing space before every dialog (prompt, confirm,
    # pause, menu selection) so the input row doesn't sit flush
    # against the previous content.
    ui_box_blank

    _ui_overlay_begin

    # Visible columns consumed by the prompt segment so far:
    #   1 (║) + 2 ("  ") + len(text) + 1 (" ") = 4 + len(text)
    # The remaining width before the right ║ is filled with
    # spaces that the user's input overwrites as they type.
    local _leoui_consumed=$(( 4 + ${#_leoui_text} ))
    local _leoui_fill=$(( UI_BOX_TOTAL - _leoui_consumed - 1 ))
    (( _leoui_fill < 0 )) && _leoui_fill=0

    printf '║  %s ' "$_leoui_text"             # border + indent + prompt + space
    printf '\033[s'                            # save cursor (right after prompt)
    printf '%*s║\n' "$_leoui_fill" ''          # spaces + right border + \n
    _ui_footer                                  # footer below the prompt
    printf '\033[u'                            # back to the input position

    read -r _leoui_input
    printf -v "$_leoui_var" '%s' "$_leoui_input"
}

# _ui_finalize_row <text>
#   After _ui_read_overlay, replace the prompt row with a clean
#   content row "║ <text> ║" and keep the footer one line below.
#
#   Pre-condition: cursor at column 0 of the footer line
#   (row R+1, where R is the prompt row).
_ui_finalize_row() {
    # 1. Clear the (current) footer row R+1.
    printf '%s' "$UI_CLEAR_LINE"
    # 2. Go up to the prompt row R and clear it.
    printf '%s%s' "$UI_CURSOR_UP" "$UI_CLEAR_LINE"
    # 3. Print the finalized content row at R; cursor moves to R+1.
    printf '║ %-*.*s ║\n' "$UI_TEXT_WIDTH" "$UI_TEXT_WIDTH" "$1"
    # 4. Print a fresh footer at R+1; cursor ends at its right side.
    _ui_footer
}

# _ui_restore_footer_at_prompt
#   After _ui_read_overlay, erase the prompt row entirely and pull
#   the footer up to that position. Used by ui_pause and by the
#   menu dispatch path - the prompt was a transient interaction
#   that should leave no trace.
#
#   Pre-condition: cursor at column 0 of the footer line (row R+1).
_ui_restore_footer_at_prompt() {
    # 1. Clear the (current) footer row R+1 - it will move up.
    printf '%s' "$UI_CLEAR_LINE"
    # 2. Go up to the prompt row R and clear it.
    printf '%s%s' "$UI_CURSOR_UP" "$UI_CLEAR_LINE"
    # 3. Reprint the footer at row R; cursor ends at its right side.
    _ui_footer
}

# ui_prompt <question> <var_name> [default]
#   Ask <question>, store the answer in <var_name>. If <default>
#   is given, pressing Enter selects it. Auto-opens a default box
#   if none is open. In non-interactive mode, silently stores the
#   default (or an empty string) without prompting.
ui_prompt() {
    local question=$1
    local var_name=$2
    local default=${3:-}
    local prompt_text answer

    if [[ -n $default ]]; then
        prompt_text="${question} [${default}]:"
    else
        prompt_text="${question}:"
    fi

    # Non-interactive fallback: use the default without prompting.
    if ! _ui_is_tty; then
        printf -v "$var_name" '%s' "$default"
        if (( UI_BOX_OPEN )); then
            ui_box_line "${question}: ${default}"
        fi
        return 0
    fi

    _ui_ensure_box
    _ui_read_overlay "$prompt_text" answer
    [[ -z $answer && -n $default ]] && answer=$default
    _ui_finalize_row "${question}: ${answer}"
    printf -v "$var_name" '%s' "$answer"
}

# ui_confirm <question> [default]
#   Yes/no prompt. Returns 0 for yes, 1 for no. Re-prompts on
#   invalid input. <default> can be:
#     ""        - no default (loops until y or n)
#     "yes"/"y" - Enter selects yes; suffix displayed as "(Y/n)"
#     "no" /"n" - Enter selects no;  suffix displayed as "(y/N)"
#   Input is trimmed of surrounding whitespace before matching.
#   In non-interactive mode the default is returned (defaulting to
#   "no" when none is provided).
ui_confirm() {
    local question=$1
    local default=${2:-}

    # Normalize default to the canonical "yes" / "no" / "".
    local default_norm=''
    case ${default,,} in
        y|yes|s|si|sí) default_norm='yes' ;;
        n|no)          default_norm='no'  ;;
    esac

    # Build the visual "(y/n)" suffix, uppercasing the default.
    local yn
    case $default_norm in
        yes) yn='(Y/n):' ;;
        no)  yn='(y/N):' ;;
        *)   yn='(y/n):' ;;
    esac
    local prompt_text="${question} ${yn}"

    # Non-interactive fallback: return the default directly.
    if ! _ui_is_tty; then
        local result=${default_norm:-no}
        local rc=1
        [[ $result == yes ]] && rc=0
        (( UI_BOX_OPEN )) && ui_box_line "${question} ${yn} ${result}"
        return "$rc"
    fi

    _ui_ensure_box

    local ans result rc
    while true; do
        _ui_read_overlay "$prompt_text" ans
        # Trim leading + trailing whitespace.
        ans="${ans#"${ans%%[![:space:]]*}"}"
        ans="${ans%"${ans##*[![:space:]]}"}"
        # Empty + default? Apply the default.
        if [[ -z $ans && -n $default_norm ]]; then
            result=$default_norm
            [[ $result == yes ]] && rc=0 || rc=1
            break
        fi
        case ${ans,,} in
            y|yes|s|si) result='yes'; rc=0; break ;;
            n|no)       result='no';  rc=1; break ;;
            *)          _ui_restore_footer_at_prompt ;;
        esac
    done

    _ui_finalize_row "${question} ${yn} ${result}"
    return "$rc"
}

# ui_pause [msg]
#   Wait for the user to press Enter. Auto-opens a default box if
#   none is open. The prompt row is erased after Enter so the box
#   stays clean. In non-interactive mode this is a no-op.
ui_pause() {
    if ! _ui_is_tty; then
        return 0
    fi

    _ui_ensure_box
    local msg=${1:-Press Enter to continue}
    local _discard

    _ui_read_overlay "${msg}..." _discard
    _ui_restore_footer_at_prompt
}

# ui_select <var_name> <prompt> <option1> [option2 ...]
#   Numbered single-choice picker. Lists <option*> as a numbered
#   list, reads a number from the user, and stores the chosen
#   option (the string, not the index) into <var_name>.
#   Auto-opens a box titled <prompt> if none is open; otherwise it
#   reuses the open box and writes <prompt> as a regular row.
#   In non-interactive mode the first option is selected.
#   Returns 0 on success, 1 if fewer than one option was passed.
ui_select() {
    local var_name=$1
    local prompt=$2
    shift 2
    local options=("$@")
    local n=${#options[@]}

    if (( n < 1 )); then
        ui_notify "ui_select requires at least one option"
        return 1
    fi

    # Non-interactive fallback: pick the first option silently.
    if ! _ui_is_tty; then
        printf -v "$var_name" '%s' "${options[0]}"
        return 0
    fi

    # Display: open a dedicated box if none is open, otherwise
    # inject the prompt as a content row inside the current box.
    local opened_here=0
    if (( ! UI_BOX_OPEN )); then
        ui_box_top "$prompt"
        opened_here=1
    else
        ui_box_line "$prompt"
        ui_box_blank
    fi

    local i
    for (( i = 0; i < n; i++ )); do
        ui_box_line "$(printf '%2d. %s' "$(( i + 1 ))" "${options[i]}")"
    done

    local choice selected
    while true; do
        _ui_read_overlay "Select option:" choice
        # Trim whitespace.
        choice="${choice#"${choice%%[![:space:]]*}"}"
        choice="${choice%"${choice##*[![:space:]]}"}"
        if [[ $choice =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= n )); then
            selected=${options[choice-1]}
            _ui_finalize_row "${prompt}: ${selected}"
            printf -v "$var_name" '%s' "$selected"
            (( opened_here )) && ui_box_bottom
            return 0
        else
            # Same pattern as ui_menu's invalid path: replace the
            # prompt row with an error notification and re-prompt.
            printf '%s' "$UI_CLEAR_LINE"
            printf '%s%s' "$UI_CURSOR_UP" "$UI_CLEAR_LINE"
            _ui_error_row "Invalid option: ${choice}"
            _ui_footer
        fi
    done
}


# =================================================================
# Menus
# =================================================================

# ui_menu <title> <array_var_name>
#   Render an interactive menu. Selectable entries are numbered
#   1..N; if the last entry is @back or @exit it is numbered 0.
#   In non-interactive mode this prints an error and returns 1 -
#   menus cannot operate without a real terminal.
ui_menu() {
    local title=$1
    local -n _entries=$2

    if ! _ui_is_tty; then
        ui_notify "ui_menu '${title}' requires an interactive terminal"
        return 1
    fi

    while true; do
        ui_box_top "$title"

        # Pass 1: assign numbers and collect actions.
        local -a numbers=()
        local -a actions=()
        local n=1
        local idx
        for idx in "${!_entries[@]}"; do
            local raw=${_entries[idx]}
            case $raw in
                ---|'')
                    numbers+=('')
                    actions+=('')
                    ;;
                *)
                    local action=${raw#*|}
                    if [[ $action == @back || $action == @exit ]]; then
                        numbers+=(0)
                        actions+=("$action")
                    else
                        numbers+=("$n")
                        actions+=("$action")
                        n=$(( n + 1 ))
                    fi
                    ;;
            esac
        done

        # Pass 2: render rows.
        for idx in "${!_entries[@]}"; do
            local raw=${_entries[idx]}
            case $raw in
                ---) ui_box_separator ;;
                '')  ui_box_blank ;;
                *)
                    local label=${raw%%|*}
                    local num=${numbers[idx]}
                    ui_box_line "$(printf '%2d. %s' "$num" "$label")"
                    ;;
            esac
        done

        # Prompt for a choice INSIDE the box (right border preserved).
        local choice
        _ui_read_overlay "Select option:" choice

        local target_action=''
        for idx in "${!numbers[@]}"; do
            if [[ -n ${numbers[idx]} && ${numbers[idx]} == "$choice" ]]; then
                target_action=${actions[idx]}
                break
            fi
        done

        if [[ -z $target_action ]]; then
            # Replace the prompt row with an error notification
            # and pause so the user can read it. Same row layout
            # as _ui_finalize_row: clear stale footer, clear
            # prompt, print error row, print fresh footer.
            printf '%s' "$UI_CLEAR_LINE"
            printf '%s%s' "$UI_CURSOR_UP" "$UI_CLEAR_LINE"
            _ui_error_row "Invalid option: ${choice}"
            _ui_footer
            ui_pause
            continue
        fi

        # Close the box before dispatching so the action can open
        # its own box cleanly (ui_box_top auto-clears).
        _ui_restore_footer_at_prompt
        ui_box_bottom

        # Built-in sentinels.
        case $target_action in
            @back) return 0 ;;
            @exit) exit 0 ;;
        esac

        # Dispatch the action (function or command with args).
        # shellcheck disable=SC2086
        $target_action
        local rc=$?

        if (( rc != 0 )); then
            ui_box_top "Error"
            ui_box_line "Action '${target_action}' failed (rc=${rc})."
            ui_pause
            ui_box_bottom
        fi
    done
}


# =================================================================
# Signal handling
# =================================================================
#
# When LeoUI is sourced from a non-interactive shell (i.e. a real
# script - the typical case), we install traps that:
#   - On normal EXIT:    close any open box, reap the spinner pid.
#   - On INT (Ctrl+C):   do the same, then exit 130.
#   - On TERM:           do the same, then exit 143.
#
# When sourced into an INTERACTIVE shell, no traps are installed -
# the user's shell session is left alone. Scripts that need
# different behavior can override the traps after sourcing.
if [[ $- != *i* ]]; then
    trap '_ui_cleanup' EXIT
    trap '_ui_cleanup; exit 130' INT
    trap '_ui_cleanup; exit 143' TERM
fi
