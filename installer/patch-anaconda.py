#!/usr/bin/python3
"""Patches the installer's copy of Anaconda for OrielOS.

- Download progress for the container deploy (modules/payloads/payload/rpm_ostree/installation.py).
  `ostree container image deploy` prints nothing until it finishes, so the installer sat on
  "Deployment starting" for the whole download. This runs the deploy in a thread and, every two
  seconds, reports how much of the image has arrived: the image's compressed size from its
  manifest (skopeo), the bytes received from the network interfaces' counters.
- OrielOS's version, such as v0.0.5, shown whole and as written (core/product.py, ui/helpers.py):
  Anaconda cuts versions to two parts and writes them in capitals in its title.
- A warning when a drive that stays is encrypted with BitLocker (modules/storage/checker/utils.py):
  Windows may ask for its recovery key once another system is installed.

Usage: patch-anaconda.py <pyanaconda directory>
Patches the files in place, and fails if any of Anaconda's code it changes has changed.
"""
import os
import sys

PROGRESS_HELPERS = '''

# OrielOS: download progress for the container deploy (see the build's patch-anaconda.py).
def _orielos_download_size(ref):
    """The image's compressed size in bytes, from its manifest, or 0 if it can't be read."""
    import json
    import subprocess

    def raw(name):
        out = subprocess.run(["skopeo", "inspect", "--raw", "docker://" + name],
                             capture_output=True, text=True, timeout=60, check=True).stdout
        return json.loads(out)

    try:
        manifest = raw(ref)
        if "manifests" in manifest:
            entry = next(m for m in manifest["manifests"]
                         if m.get("platform", {}).get("architecture") == "amd64")
            repository = ref.split("@")[0] if "@" in ref else ref.rsplit(":", 1)[0]
            manifest = raw(repository + "@" + entry["digest"])
        return sum(layer["size"] for layer in manifest["layers"])
    except Exception:  # pylint: disable=broad-except
        log.exception("OrielOS: could not read the image's size")
        return 0


def _orielos_received_bytes():
    """Bytes received so far by every network interface except loopback."""
    import glob

    total = 0
    for path in glob.glob("/sys/class/net/*/statistics/rx_bytes"):
        if path.startswith("/sys/class/net/lo/"):
            continue
        try:
            with open(path) as counter:
                total += int(counter.read())
        except (OSError, ValueError):
            pass
    return total


def _orielos_deploy_with_progress(task, args, ref):
    """Run the deploy in a thread and report the download's progress meanwhile."""
    import threading
    import time

    total = _orielos_download_size(ref)
    start_bytes = _orielos_received_bytes()
    start_time = time.monotonic()
    outcome = {}

    def deploy():
        try:
            safe_exec_program("ostree", args, env_add={"LC_ALL": "C.UTF-8"})
        except Exception as error:  # pylint: disable=broad-except
            outcome["error"] = error

    worker = threading.Thread(target=deploy, name="OrielOSDeploy", daemon=True)
    worker.start()
    gb = 1000 ** 3
    while True:
        worker.join(2)
        if not worker.is_alive():
            break
        got = max(0, _orielos_received_bytes() - start_bytes)
        elapsed = time.monotonic() - start_time
        if total and got >= total:
            message = _("Download complete. Installing OrielOS...")
        elif total:
            message = _("Downloading OrielOS: {got:.1f} of {total:.1f} GB ({percent}%)").format(
                got=got / gb, total=total / gb, percent=min(99, got * 100 // total))
            if got > 0 and elapsed > 10:
                minutes = round((total - got) / (got / elapsed) / 60)
                message += ", " + (_("about {} minutes left").format(minutes) if minutes > 1
                                   else _("about a minute left"))
        else:
            message = _("Downloading OrielOS: {:.1f} GB").format(got / gb)
        task.report_progress(message)
    if "error" in outcome:
        raise outcome["error"]
'''

BITLOCKER_CHECK = '''

# OrielOS: warn about BitLocker (see the build's patch-anaconda.py).
def verify_orielos_bitlocker(storage, constraints, report_error, report_warning):
    """Warn when a drive that stays is encrypted with BitLocker.

    Windows may ask for its BitLocker recovery key once another system is installed, because
    the PC then starts differently.

    :param storage: a storage to check
    :param constraints: a dictionary of constraints
    :param report_error: a function for error reporting
    :param report_warning: a function for warning reporting
    """
    for device in storage.devices:
        if device.exists and device.format.type == "bitlocker":
            report_warning(_(
                "%(name)s (%(size)s) is encrypted with BitLocker. Once OrielOS is installed, "
                "Windows may ask for its BitLocker recovery key the next time it starts. Make "
                "sure you have the key before you install: it's in your Microsoft account at "
                "aka.ms/myrecoverykey, or in Windows' BitLocker settings."
            ) % {"name": device.name, "size": device.size})
'''

# Each file: its path under pyanaconda, then (old, new) replacements that must each match once,
# then text to add at the end.
PATCHES = [
    ("modules/payloads/payload/rpm_ostree/installation.py", [(
        '''            safe_exec_program(
                "ostree",
                args,
                env_add={"LC_ALL": "C.UTF-8"},
            )
        else:''',
        '''            _orielos_deploy_with_progress(self, args, ref)
        else:''',
    )], PROGRESS_HELPERS),
    ("core/product.py", [(
        "    if version.count('.') >= 2:\n",
        "    # OrielOS: keep vMAJOR.MINOR.PATCH whole.\n"
        "    if version.count('.') >= 2 and not version.startswith('v'):\n",
    )], ""),
    ("ui/helpers.py", [(
        '"productVersion": get_product_version().upper()',
        '"productVersion": get_product_version()',
    )], ""),
    # The module makes its checker, with the list of checks, when it's imported, so the new
    # check goes before the classes rather than at the end.
    ("modules/storage/checker/utils.py", [(
        "\n\nclass StorageCheckerReport:\n",
        BITLOCKER_CHECK + "\n\nclass StorageCheckerReport:\n",
    ), (
        "        self.add_check(verify_lvm_destruction)\n",
        "        self.add_check(verify_lvm_destruction)\n"
        "        self.add_check(verify_orielos_bitlocker)\n",
    )], ""),
]


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    root = sys.argv[1]
    for rel, replacements, addition in PATCHES:
        path = os.path.join(root, rel)
        with open(path, encoding="utf-8") as source:
            text = source.read()
        if "OrielOS:" in text:
            sys.exit(f"patch-anaconda.py: {rel} is already patched")
        for old, new in replacements:
            if text.count(old) != 1:
                sys.exit(f"patch-anaconda.py: Anaconda's {rel} has changed; update the patch")
            text = text.replace(old, new)
        if addition:
            text = text.rstrip("\n") + "\n" + addition
        with open(path, "w", encoding="utf-8") as source:
            source.write(text)
        print(f"patched {rel}")


if __name__ == "__main__":
    main()
