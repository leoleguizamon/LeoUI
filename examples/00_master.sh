#!/usr/bin/env bash
# =================================================================
#  LeoUI - Master example
# =================================================================
#  This single script exercises EVERY public function of the
#  library. It is meant to be read top-to-bottom as a tutorial:
#  each menu entry calls a small demo function that focuses on
#  one feature, with inline comments explaining what is happening.
#
#  Run it from this directory:
#      ./00_master.sh
# =================================================================

# Resolve the library path relative to THIS script, so the example
# can be launched from any working directory.
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/../leoui.sh"

# -----------------------------------------------------------------
# ui_init [author] [width]
#   Optional initialization.
#     - author: signature shown on the right side of every footer
#               (default "LeoUI").
#     - width:  total box width in columns (default 52).
#   To customize the box size, pass a second argument, e.g.
#       ui_init "leo" 60
# -----------------------------------------------------------------
ui_init "leo"


# =================================================================
# Demo 1: drawing primitives
#
#   ui_box_top <title>     - opens a new box (auto-clears screen)
#   ui_box_line <text>     - appends a content row
#   ui_box_paragraph <txt> - appends word-wrapped text
#   ui_box_blank           - appends an empty row
#   ui_box_separator       - appends a horizontal divider (╠═══╣)
#   ui_box_bottom          - closes the box
# =================================================================
demo_drawing() {
    # Every demo opens its own box. ui_box_top ALWAYS clears the
    # screen first, so only one box is ever visible at a time.
    ui_box_top "Drawing primitives"

    ui_box_line "This is a content row (ui_box_line)."
    ui_box_line "Rows are truncated to 48 visible columns max."
    ui_box_blank                        # an empty row for breathing space
    ui_box_line "Below this line you'll see a separator:"
    ui_box_separator                    # ╠═══════╣ divider
    ui_box_line "And these rows live in a 'second section'."
    ui_box_blank

    # ui_box_paragraph word-wraps a long string into multiple rows.
    ui_box_paragraph "This long sentence is automatically wrapped \
across several rows by ui_box_paragraph so you don't have to call \
ui_box_line repeatedly for prose text."

    # ui_pause adds a blank row above itself automatically and
    # waits for the user to press Enter. Renders inside the box.
    ui_pause "Press Enter to return to the menu"

    # Close the box. Required to leave the box state clean.
    ui_box_bottom
}


# =================================================================
# Demo 2: ui_run - command execution with spinner feedback
#
#   ui_run <msg> <cmd> [args...]
#     Runs the command in the background, animates a spinner
#     while it lives, then replaces the line with "Listo [✔]"
#     or "Error [✖]" based on the REAL exit code. Returns that
#     exit code. stdout/stderr of the command are silenced.
# =================================================================
demo_run() {
    ui_box_top "ui_run - tasks with feedback"
    ui_box_line "Each row below is a real backgrounded command:"
    ui_box_blank

    # Successful commands - the spinner ends with "Listo [✔]".
    ui_run "Quick sleep"       sleep 0.4
    ui_run "Another quick one" sleep 0.4
    ui_run "true (no-op)"      true

    # A failing command - the spinner ends with "Error [✖]" and
    # ui_run returns the command's real exit code. We do NOT let
    # the script abort on failure because we chain with `|| true`.
    ui_run "false (always fails)" false || true

    # You can capture and use the return code explicitly.
    if ui_run "Maybe-failing job" bash -c "exit 0"; then
        ui_box_line "The job above succeeded."
    else
        ui_box_line "The job above failed."
    fi

    ui_pause
    ui_box_bottom
}


# =================================================================
# Demo 3: ui_notify - non-fatal error notifications
#
#   ui_notify <msg>   shows "msg ... Error [✖]" and continues.
#   ui_error  <msg>   same, but also exits the program (exit 1).
#                     We do NOT call ui_error from this demo
#                     because it would terminate the menu.
# =================================================================
demo_notify() {
    ui_box_top "Notifications"
    ui_box_line "ui_notify reports an error without exiting."
    ui_box_line "Useful when something fails but you want to"
    ui_box_line "keep going."

    # Notice the automatic blank row before the notification.
    ui_notify "Disk usage above 80%"
    ui_notify "Network connection unstable"

    ui_box_line "(ui_error would do the same and then exit 1.)"

    ui_pause
    ui_box_bottom
}


# =================================================================
# Demo 4: ui_prompt - ask for free-form text input
#
#   ui_prompt <question> <var_name> [default]
#     Renders an in-box prompt with the right border preserved.
#     After Enter, the row is finalized as "Question: answer".
# =================================================================
demo_prompt() {
    ui_box_top "ui_prompt"
    ui_box_line "ui_prompt asks for free-form text input."
    ui_box_line "The right border stays drawn during the read."

    # Without default: an empty answer is stored as empty string.
    local name
    ui_prompt "What is your name?" name

    # With default: pressing Enter selects "stable" automatically.
    local branch
    ui_prompt "Branch to checkout?" branch "stable"

    ui_box_blank
    ui_box_line "You said:"
    ui_box_line "  name=${name:-<empty>}"
    ui_box_line "  branch=${branch}"

    ui_pause
    ui_box_bottom
}


# =================================================================
# Demo 5: ui_confirm - yes/no questions
#
#   ui_confirm <question> [default]
#     Returns 0 for yes, 1 for no. Re-prompts on invalid input.
#     Accepts y/yes/s/si/sí and n/no (case insensitive).
#     Whitespace around the answer is trimmed automatically.
#     <default>:
#       "yes"/"y"  - Enter selects yes, prompt shows "(Y/n)"
#       "no"/"n"   - Enter selects no,  prompt shows "(y/N)"
#       (omitted)  - no default, loops until y or n is typed
# =================================================================
demo_confirm() {
    ui_box_top "ui_confirm"
    ui_box_line "ui_confirm asks a yes/no question."
    ui_box_line "Use it for guarded actions like 'are you sure?'."

    # Without default - the user must type y or n explicitly.
    if ui_confirm "Proceed with the operation?"; then
        ui_box_line "Branch taken: YES."
    else
        ui_box_line "Branch taken: NO."
    fi

    # With default=yes - the prompt shows "(Y/n)" and pressing
    # Enter without typing anything selects yes.
    if ui_confirm "Show extra detail?" yes; then
        ui_box_line "Extra detail row 1"
        ui_box_line "Extra detail row 2"
    fi

    # With default=no - prompt shows "(y/N)".
    if ui_confirm "Delete temporary files?" no; then
        ui_box_line "User explicitly accepted deletion."
    else
        ui_box_line "Skipped (default)."
    fi

    ui_pause
    ui_box_bottom
}


# =================================================================
# Demo 5b: ui_select - numbered single-choice picker
#
#   ui_select <var_name> <prompt> <opt1> [opt2 ...]
#     Lists the options as a numbered menu, reads a number, and
#     stores the CHOSEN STRING (not the index) into <var_name>.
#     Reuses the open box if one exists, otherwise opens a new
#     box titled <prompt>.
# =================================================================
demo_select() {
    ui_box_top "ui_select"
    ui_box_line "ui_select prompts for a numbered choice."
    ui_box_blank

    local theme env
    ui_select theme "Pick a theme"       "Dark" "Light" "Auto"
    ui_select env   "Pick an environment" "dev" "staging" "production"

    ui_box_blank
    ui_box_line "You picked:"
    ui_box_line "  theme=${theme}"
    ui_box_line "  env=${env}"

    ui_pause
    ui_box_bottom
}


# =================================================================
# Demo 6: nested menus with @back
#
#   A submenu is just a function that calls ui_menu again. By
#   convention its last entry is "Back|@back", which returns to
#   the parent menu.
# =================================================================

apply_dark() {
    ui_box_top "Theme: dark"
    ui_run "Switching to dark theme" sleep 0.4
    ui_pause
    ui_box_bottom
}

apply_light() {
    ui_box_top "Theme: light"
    ui_run "Switching to light theme" sleep 0.4
    ui_pause
    ui_box_bottom
}

menu_themes() {
    # Menu entries are plain strings: "Label|action".
    # @back is a built-in sentinel that returns to the parent menu.
    local entries=(
        "Dark|apply_dark"
        "Light|apply_light"
        "---"
        "Back|@back"
    )
    ui_menu "Themes" entries
}


# =================================================================
# Demo 7: a deliberately failing action (error path of ui_menu)
#
#   When an action returns a non-zero exit code, the menu shows
#   an error box, waits for Enter, and then redraws itself. The
#   program does NOT abort, even with `set -e` at the top.
# =================================================================
failing_action() {
    ui_box_top "Failing action"
    ui_box_line "This action will exit with status 42."
    ui_box_line "Watch how the menu handles the error gracefully."
    ui_pause
    ui_box_bottom
    return 42
}


# =================================================================
# Main menu
#
#   ui_menu <title> <array_var_name>
#     - Selectable entries are numbered 1..N in order.
#     - If the LAST entry is @back or @exit, it is numbered 0.
#     - "---"  renders as a horizontal divider.
#     - ""     renders as a blank row.
#     - The library auto-validates input and redraws on errors.
# =================================================================
menu_main() {
    local entries=(
        "Drawing primitives|demo_drawing"
        "ui_run (spinner)|demo_run"
        "ui_notify|demo_notify"
        "ui_prompt|demo_prompt"
        "ui_confirm|demo_confirm"
        "ui_select|demo_select"
        "---"
        "Nested submenu (themes)|menu_themes"
        "Failing action|failing_action"
        "---"
        "Exit|@exit"
    )
    ui_menu "LeoUI master demo" entries
}

# Entry point.
menu_main
