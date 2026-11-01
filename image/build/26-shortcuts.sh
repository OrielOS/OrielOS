#!/usr/bin/env bash
# Windows keyboard shortcuts and plain names for the system tools. Gives System Monitor
# Ctrl+Shift+Esc, KRunner Win+R and Spectacle a Win+PrtSc action that saves a full screenshot
# without a dialog, moves the Spectacle shortcuts those keys clash with, and renames System
# Monitor, Spectacle and Dolphin to Process Manager, Screenshot and Files, gives Win+. to OrielOS's
# emoji panel instead of Plasma's emoji selector, and renames the taskbar widget
# to Taskbar. System Settings gives Win+I and its place in Start to OrielOS's Settings app, and
# Plasma's screen picker gives Win+P to OrielOS's Display mode panel. The
# KWin shortcuts (Win+Tab and Win+Up/Down) are in system/etc/skel/.config/kglobalshortcutsrc.
set -Eeuo pipefail
if [[ -n "${ORIELOS_BUILD_TRACE:-}" ]]; then set -x; fi

# shellcheck source-path=SCRIPTDIR source=desktop-entry.sh
source "$(dirname "${BASH_SOURCE[0]}")/desktop-entry.sh"

script=image/build/26-shortcuts.sh
apps=/usr/share/applications
accel=/usr/share/kglobalaccel

# Replace the shortcuts of one group in a desktop entry, failing unless the group had exactly
# the expected ones.
#   set_shortcuts <file> <group> <old shortcuts> <new shortcuts>
set_shortcuts() {
    local file="$1" group="$2" old="$3" new="$4" tmp
    [[ -f "$file" ]] || die "$file does not exist; its packaging changed, so update $script"
    tmp="$(mktemp)"
    awk -v group="[$group]" -v old="X-KDE-Shortcuts=$old" -v new="X-KDE-Shortcuts=$new" '
        /^\[/ { inside = ($0 == group) }
        inside && $0 == old { $0 = new; done++ }
        { print }
        END { exit done == 1 ? 0 : 1 }
    ' "$file" >"$tmp" || {
        rm -f "$tmp"
        die "[$group] in $file does not have X-KDE-Shortcuts=$old; update $script"
    }
    cat "$tmp" >"$file"
    rm -f "$tmp"
}

# kglobalaccel reads the shortcuts of an app from its entry in /usr/share/kglobalaccel. Some of
# those are hard links to the menu entry, which sed -i would split, so after the menu entry is
# changed the kglobalaccel one becomes a link to it, as Dolphin's and Spectacle's already are.
# Put search words at the front of an entry's English keywords, so Start finds the tool by what
# people want to do with it. An entry without keywords gets them after its GenericName.
#   add_keywords <file> <generic name> <words, each ending in ;>
add_keywords() {
    local file="$1" generic="$2" words="$3"
    if grep -q '^Keywords=' "$file"; then
        sed -i "s/^Keywords=/Keywords=${words}/" "$file"
    else
        sed -i "s/^GenericName=${generic}\$/&\nKeywords=${words}/" "$file"
    fi
    grep -q "^Keywords=${words}" "$file" || die "could not add keywords to $file; update $script"
}

link_accel() {
    local name="$1"
    [[ -e "$accel/$name" ]] || die "$accel/$name does not exist; update $script"
    ln -sf "$apps/$name" "$accel/$name"
}

# Process Manager: System Monitor, on Ctrl+Shift+Esc as well as Plasma's Win+Esc.
monitor=$apps/org.kde.plasma-systemmonitor.desktop
rename_entry "$monitor" "System Monitor" "Process Manager" "System monitor" "$script"
add_keywords "$monitor" "System monitor" "processes;tasks;end task;not responding;performance;cpu;memory;"
set_shortcuts "$monitor" "Desktop Entry" "Meta+Esc" "Ctrl+Shift+Esc,Meta+Esc"
link_accel org.kde.plasma-systemmonitor.desktop

# Run: Win+R opens OrielOS's Run box (its own desktop entry gives it the key), KRunner keeps Alt+F2
# and the Search key, and Alt+Space goes to the window menu, as in Windows. Spectacle's region
# recording had Win+R as its second shortcut; it keeps Win+Shift+R.
set_shortcuts "$accel/org.kde.krunner.desktop" "Desktop Entry" "Alt+Space,Alt+F2,Search" "Alt+F2,Search"

# Emoji: Win+. and Win+; open OrielOS's emoji panel (its own desktop entry gives it the keys), with
# kaomoji, symbols and the clipboard as well; Plasma's emoji selector keeps its other shortcut.
set_shortcuts "$accel/org.kde.plasma.emojier.desktop" "Desktop Entry" "Meta+.,Meta+Ctrl+Alt+Shift+Space" "Meta+Ctrl+Alt+Shift+Space"

# Screenshot: Spectacle. Win+Shift+S (a rectangular region) is Plasma's default. Win+PrtSc
# saves the whole desktop to Pictures/Screenshots without opening Spectacle's window, as on
# Windows, and the active window moves to Alt+PrtSc, its Windows key.
spectacle=$apps/org.kde.spectacle.desktop
rename_entry "$spectacle" Spectacle Screenshot "Screen capture" "$script"
add_keywords "$spectacle" "Screen capture" "screenshot;screen capture;snip;print screen;capture;"
set_shortcuts "$spectacle" "Desktop Action RecordRegion" "Meta+Shift+R,Meta+R" "Meta+Shift+R"
set_shortcuts "$spectacle" "Desktop Action ActiveWindowScreenShot" "Meta+Print" "Alt+Print"
grep -q '^Actions=.*;$' "$spectacle" || die "$spectacle has no Actions= list ending in ;; update $script"
sed -i 's/^Actions=\(.*\)$/Actions=\1FullScreenToFile;/' "$spectacle"
cat >>"$spectacle" <<'EOF'

[Desktop Action FullScreenToFile]
Name=Save a Screenshot of the Entire Desktop
Exec=/usr/bin/spectacle --background --fullscreen
X-KDE-Shortcuts=Meta+Print
EOF

# Files: Dolphin. Win+E is Plasma's default.
rename_entry "$apps/org.kde.dolphin.desktop" Dolphin Files "File manager" "$script"

# Taskbar: Plasma's icons-only task manager, the widget the taskbar's apps are in, so its menu
# says "Configure Taskbar…" (the menu's pin wording is in plasma/translations). Only the English
# names change; other languages keep Plasma's translations.
icontasks=/usr/share/plasma/plasmoids/org.kde.plasma.icontasks/metadata.json
jq -e '.KPlugin.Name == "Icons-Only Task Manager"' "$icontasks" >/dev/null ||
    die "$icontasks is no longer named Icons-Only Task Manager; update $script"
tmp="$(mktemp)"
jq '.KPlugin.Name = "Taskbar" | if .KPlugin["Name[en_GB]"] then .KPlugin["Name[en_GB]"] = "Taskbar" else . end' \
    "$icontasks" >"$tmp"
install -m 0644 "$tmp" "$icontasks"
rm -f "$tmp"

# Settings: OrielOS's own app (apps/settings) has Win+I and is Settings in Start, so System
# Settings gives up both. It stays installed, because parts of Plasma open their pages in it.
# kglobalaccel's entry for it is a link to the menu entry, so one change covers both.
settings=$apps/systemsettings.desktop
set_shortcuts "$settings" "Desktop Entry" "Tools,Meta+I" "Tools"
[[ "$(head -n1 "$settings")" == "[Desktop Entry]" ]] || die "$settings doesn't start with [Desktop Entry]; update $script"
sed -i '1a NoDisplay=true' "$settings"

# Display mode: OrielOS's own panel (apps/displaymode) has Win+P, so Plasma's screen picker
# keeps only the Display key. Its entry exists only in kglobalaccel's folder.
set_shortcuts "$accel/org.kde.kscreen.desktop" "Desktop Action ShowOSD" "Display,Meta+P" "Display"

# Plasma's defaults that OrielOS keeps; fail if a package update moves one of them.
grep -qxF 'X-KDE-Shortcuts=Meta+E' "$apps/org.kde.dolphin.desktop" || die "Dolphin is no longer on Meta+E; update $script"
grep -qxF 'X-KDE-Shortcuts=Print,Meta+Shift+S' "$spectacle" || die "Spectacle is no longer on Meta+Shift+S; update $script"
grep -q '^X-KDE-Shortcuts=Meta+\.,' "$apps/org.kde.plasma.emojier.desktop" || die "the emoji picker is no longer on Meta+.; update $script"

# No two app shortcuts may share a key. Each entry's shortcuts are counted once per file name,
# because some kglobalaccel entries are links to the menu entries.
dupes="$(for f in "$accel"/*.desktop "$apps"/*.desktop; do
    sed -n 's/^X-KDE-Shortcuts=//p' "$f" | tr ',' '\n' | sed "s|^|${f##*/} |"
done | sort -u | awk 'NF == 2 && $2 != "none" {print $2}' | sort | uniq -d)"
[[ -z "$dupes" ]] || die "more than one desktop entry uses these shortcuts: $(paste -sd ' ' - <<<"$dupes")"
