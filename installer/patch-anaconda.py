#!/usr/bin/python3
"""Adds download progress to Anaconda's container deploy step.

`ostree container image deploy` prints nothing until it finishes, so the installer sat on
"Deployment starting" for the whole download. This runs the deploy in a thread and, every two
seconds, reports how much of the image has arrived: the image's compressed size from its manifest
(skopeo), the bytes received from the network interfaces' counters.

Usage: patch-anaconda.py <installation.py> (patched in place; fails if Anaconda's code changed)
"""
import sys

ANCHOR = '''            safe_exec_program(
                "ostree",
                args,
                env_add={"LC_ALL": "C.UTF-8"},
            )
        else:'''

REPLACEMENT = '''            _orielos_deploy_with_progress(self, args, ref)
        else:'''

HELPERS = '''

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


def main():
    path = sys.argv[1]
    with open(path, encoding="utf-8") as source:
        text = source.read()
    if text.count(ANCHOR) != 1:
        sys.exit("patch-anaconda.py: Anaconda's deploy code has changed; update the patch")
    if "_orielos_deploy_with_progress" in text:
        sys.exit("patch-anaconda.py: already patched")
    text = text.replace(ANCHOR, REPLACEMENT).rstrip("\n") + "\n" + HELPERS
    with open(path, "w", encoding="utf-8") as source:
        source.write(text)


if __name__ == "__main__":
    main()
