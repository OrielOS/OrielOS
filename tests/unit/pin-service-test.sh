#!/usr/bin/env bash
# Unit tests for image/system/usr/libexec/orielos/pin-service's first-run setup PIN: "stage", which
# only the setup's own user may ask for, while the setup runs and before anyone has an account, and
# --apply-staged, which gives the staged PIN to the account the setup made. The service is loaded as
# a module with made-up accounts, folders in a temporary folder, and a stand-in for systemd-creds
# that doesn't encrypt. Prints PASS/FAIL per case and exits 1 if any case fails.
#
# Usage: tests/unit/pin-service-test.sh
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SERVICE="$ROOT/image/system/usr/libexec/orielos/pin-service"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/bin"
cat >"$WORK/bin/systemd-creds" <<'EOF'
#!/usr/bin/env bash
# systemd-creds encrypt --name=N --with-key=auto - OUT, or decrypt --name=N IN -
set -euo pipefail
case "$1" in
encrypt) cat >"${!#}" ;;
decrypt) cat "$3" ;;
*) exit 2 ;;
esac
EOF
chmod +x "$WORK/bin/systemd-creds"

PATH="$WORK/bin:$PATH" python3 -I - "$SERVICE" "$WORK" <<'PY'
import importlib.machinery
import importlib.util
import os
import shutil
import sys
from types import SimpleNamespace

service_path, work = sys.argv[1], sys.argv[2]
loader = importlib.machinery.SourceFileLoader("pin_service", service_path)
spec = importlib.util.spec_from_loader("pin_service", loader)
pin = importlib.util.module_from_spec(spec)
loader.exec_module(pin)
# A cheap hash keeps the test quick; the service's own settings are checked below.
assert pin.SCRYPT["n"] >= 2**15
pin.SCRYPT = {"n": 2**4, "r": 8, "p": 1}

accounts = {}


def account(name, uid):
    return SimpleNamespace(pw_name=name, pw_uid=uid)


def getpwnam(name):
    if name not in accounts:
        raise KeyError(name)
    return accounts[name]


pin.pwd = SimpleNamespace(getpwall=lambda: list(accounts.values()), getpwnam=getpwnam,
                          getpwuid=lambda uid: next(a for a in accounts.values() if a.pw_uid == uid))
SETUP = account("plasma-setup", 973)
passed = failed = 0


def reset():
    shutil.rmtree(f"{work}/root", ignore_errors=True)
    os.makedirs(f"{work}/root/pin")
    os.makedirs(f"{work}/root/pin-info")
    pin.STORE = f"{work}/root/pin"
    pin.INFO = f"{work}/root/pin-info"
    pin.STAGED = f"{work}/root/pin/staged.cred"
    pin.SETUP_DONE = f"{work}/root/plasma-setup-done"
    accounts.clear()
    accounts["plasma-setup"] = SETUP


def finish_setup(user="nathan", uid=1000):
    if user:
        accounts[user] = account(user, uid)
    open(pin.SETUP_DONE, "w").close()


def check(name, ok, detail=""):
    global passed, failed
    if ok:
        print(f"PASS  {name}")
        passed += 1
    else:
        print(f"FAIL  {name}\n      {detail}")
        failed += 1


reset()
answer = pin.stage(SETUP, "nathan", "1234")
staged = open(pin.STAGED).read() if os.path.exists(pin.STAGED) else ""
check("the setup stages a PIN for the account it will create", answer == {"ok": True} and '"user": "nathan"' in staged, answer)
check("the staged PIN is kept as a hash, never as typed", '"1234"' not in staged and '"hash"' in staged, staged)

answer = pin.stage(SETUP, "nathan", "")
check("an empty PIN takes the staged one back", answer == {"ok": True} and not os.path.exists(pin.STAGED), answer)

reset()
accounts["nathan"] = account("nathan", 1000)
answer = pin.handle({"op": "stage", "user": "eve", "pin": "1234"}, 1000)
check("only the setup's own user may stage", answer["ok"] is False and not os.path.exists(pin.STAGED), answer)

reset()
accounts["admin"] = account("admin", 1000)
answer = pin.stage(SETUP, "admin", "1234")
check("nothing is staged once someone has an account", answer["ok"] is False and not os.path.exists(pin.STAGED), answer)

reset()
open(pin.SETUP_DONE, "w").close()
answer = pin.stage(SETUP, "nathan", "1234")
check("nothing is staged after the setup has finished", answer["ok"] is False and not os.path.exists(pin.STAGED), answer)

reset()
results = [pin.stage(SETUP, "nathan", p)["ok"] for p in ("123", "1234567890123", "12a4", "١٢٣٤")]
results.append(pin.stage(SETUP, "", "1234")["ok"])
results.append(pin.stage(SETUP, "../x", "1234")["ok"])
check("short, long and non-digit PINs and odd names are refused", results == [False] * 6 and not os.path.exists(pin.STAGED), results)

reset()
check("applying with nothing staged does nothing", "no PIN" in pin.apply_staged() and os.listdir(pin.STORE) == [])

reset()
pin.stage(SETUP, "nathan", "1234")
message = pin.apply_staged()
check("before the setup finishes, the PIN stays staged", os.path.exists(pin.STAGED) and not os.path.exists(f"{pin.STORE}/1000.cred"), message)

reset()
pin.stage(SETUP, "nathan", "246810")
finish_setup()
message = pin.apply_staged()
info = open(f"{pin.INFO}/nathan.qml").read() if os.path.exists(f"{pin.INFO}/nathan.qml") else ""
check("once the setup has finished, the account gets the PIN", pin.check(1000, "246810") == {"ok": True}, message)
check("a wrong PIN still fails", pin.check(1000, "135790")["ok"] is False)
check("the sign-in screen learns the PIN's length", "pinLength: 6" in info, info)
check("the staged PIN is forgotten", not os.path.exists(pin.STAGED))
check("the account's own record has no account name in it", '"user"' not in open(f"{pin.STORE}/1000.cred").read())

reset()
pin.stage(SETUP, "nathan", "1234")
finish_setup(user=None)
message = pin.apply_staged()
check("if the account wasn't made, the PIN is dropped", not os.path.exists(pin.STAGED) and not os.listdir(pin.INFO), message)

reset()
pin.stage(SETUP, "nathan", "1234")
finish_setup(uid=500)
message = pin.apply_staged()
check("a system account never gets the PIN", not os.path.exists(pin.STAGED) and not os.path.exists(f"{pin.STORE}/500.cred"), message)

print(f"{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
PY
