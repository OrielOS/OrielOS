#!/usr/bin/env bash
# Unit tests for image/system/usr/libexec/orielos/steam-default-proton, which makes GE-Proton the
# default for Windows games in Steam from the Store, once, only while Steam is closed and never
# over a default the user chose. Each case uses a made-up home folder, a stub flatpak and a
# made-up GE-Proton extension. Prints PASS/FAIL per case and exits 1 if any case fails.
#
# Usage: tests/unit/steam-default-proton-test.sh
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/image/system/usr/libexec/orielos/steam-default-proton"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PASSED=0
FAILED=0
OUT=""
RC=0

CONFIG_DIR=".var/app/com.valvesoftware.Steam/.local/share/Steam/config"

check() {
    local name="$1"
    shift
    if "$@"; then
        printf 'PASS  %s\n' "$name"
        PASSED=$((PASSED + 1))
    else
        printf 'FAIL  %s\n      output: %s\n' "$name" "$OUT"
        FAILED=$((FAILED + 1))
    fi
}

# A fresh home folder with Steam's settings (from stdin, or none), GE-Proton installed and
# Steam closed.
setup() {
    rm -rf "${WORK:?}"/*
    mkdir -p "$WORK/home/$CONFIG_DIR" "$WORK/bin" "$WORK/ge/share/steam/compatibilitytools.d/Proton-GE"
    if [[ "${1:-}" != none ]]; then
        cat >"$WORK/home/$CONFIG_DIR/config.vdf"
    fi
    cat >"$WORK/ge/share/steam/compatibilitytools.d/Proton-GE/compatibilitytool.vdf" <<'VDF'
"compatibilitytools"
{
  "compat_tools"
  {
    "Proton-GE" // the name Steam uses
    {
      "install_path" "."
      "display_name" "GE-Proton (Flatpak)"
    }
  }
}
VDF
    cat >"$WORK/bin/flatpak" <<'SH'
#!/usr/bin/env bash
[[ -e "$STUB_RUNNING" ]] && printf 'com.valvesoftware.Steam\n'
exit 0
SH
    chmod +x "$WORK/bin/flatpak"
}

run() {
    RC=0
    OUT="$(HOME="$WORK/home" XDG_STATE_HOME="$WORK/state" PATH="$WORK/bin:$PATH" \
        ORIELOS_GE_PROTON_DIR="$WORK/ge" STUB_RUNNING="$WORK/running" python3 "$SCRIPT" 2>&1)" || RC=$?
}

config() {
    cat "$WORK/home/$CONFIG_DIR/config.vdf"
}

# The default's tool name, read back with the script's own parser.
default_tool() {
    python3 - "$WORK/home/$CONFIG_DIR/config.vdf" "$SCRIPT" <<'PY'
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("sdp", sys.argv[2])
module = importlib.util.module_from_spec(importlib.util.spec_from_loader("sdp", loader))
loader.exec_module(module)
block = module.parse(open(sys.argv[1], encoding="utf-8").read())
for key in ["InstallConfigStore", "Software", "Valve", "Steam", "CompatToolMapping", "0"]:
    block = module.child(block, key) or []
print(next((v for k, v in block if k == "name"), ""))
PY
}

STEAM_CONFIG='"InstallConfigStore"
{
	"Software"
	{
		"Valve"
		{
			"Steam"
			{
				"AutoUpdateWindowEnabled"		"0"
				"Quoted"		"say \"hi\" C:\\Games"
				"CompatToolMapping"
				{
					"252950"
					{
						"name"		"proton_experimental"
						"config"		""
						"priority"		"250"
					}
				}
			}
		}
	}
}'

setup <<<"$STEAM_CONFIG"
run
check "sets GE-Proton as Steam's default" test "$RC" -eq 0 -a "$(default_tool)" == Proton-GE
check "keeps a game's own choice" grep -qF '"252950"' <(config)
check "keeps the other settings and their escapes" grep -qF '"Quoted"		"say \"hi\" C:\\Games"' <(config)
check "keeps a copy of the settings it changed" test -s "$WORK/home/$CONFIG_DIR/config.vdf.orielos-before-default"
check "notes that it's done" test -s "$WORK/state/orielos/steam-default-proton"

# The user then picks Valve's Proton as the default: the next run leaves it.
sed -i 's/"Proton-GE"/"proton_9"/' "$WORK/home/$CONFIG_DIR/config.vdf"
run
check "never changes the default again once it's done" test "$RC" -eq 0 -a "$(default_tool)" == proton_9

setup <<<"${STEAM_CONFIG/\"252950\"/\"0\"}"
run
check "leaves a default Steam already has" test "$RC" -eq 0 -a "$(default_tool)" == proton_experimental
check "and notes it, so it doesn't look again" test -s "$WORK/state/orielos/steam-default-proton"

setup <<<"$STEAM_CONFIG"
: >"$WORK/running"
run
check "changes nothing while Steam runs" test "$RC" -eq 0 -a -z "$(default_tool)"
check "and tries again later" test ! -e "$WORK/state/orielos/steam-default-proton"

setup <<<"$STEAM_CONFIG"
rm -rf "$WORK/ge"
run
check "changes nothing until GE-Proton is installed" test "$RC" -eq 0 -a -z "$(default_tool)"

setup none
run
check "does nothing before Steam has run" test "$RC" -eq 0 -a ! -e "$WORK/state/orielos/steam-default-proton"

setup <<<'"InstallConfigStore" { "Software" {'
run
check "refuses settings it can't read, changing nothing" test "$RC" -eq 1 -a "$(config)" == '"InstallConfigStore" { "Software" {'

printf '\n%d passed, %d failed\n' "$PASSED" "$FAILED"
[[ "$FAILED" -eq 0 ]]
